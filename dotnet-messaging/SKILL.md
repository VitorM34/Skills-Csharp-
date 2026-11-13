---
name: dotnet-messaging
description: Implementar e revisar mensageria assíncrona em .NET - integration events, event bus, escolha entre Azure Service Bus / Event Grid / Event Hubs / RabbitMQ / MassTransit / NServiceBus, Transactional Outbox, competing consumers, publisher-subscriber, filas e tópicos, dead-letter, poison messages, idempotência, entrega at-least-once, ordenação, versionamento de mensagens, claim check, e uso correto do SDK Azure.Messaging.ServiceBus (cliente singleton, ServiceBusProcessor, settlement, lock, prefetch). Use quando o usuário pedir comunicação por eventos/filas entre serviços, publicar evento após salvar no banco, processar mensagens ou revisar consumidores/produtores. Based on official Microsoft Learn docs (.NET microservices guide, Azure Architecture Center, Azure Service Bus).
---

# Mensageria em .NET (eventos, filas, outbox)

Só afirmar o que a doc oficial diz (fontes no fim). Teoria e padrões (saga, idempotent consumer, CQRS): `dotnet-distributed-patterns`. Visão de microsserviços: `dotnet-microservices`. Hosting de consumidores: `aspnet-hosted-services`. Observabilidade: `dotnet-observability`. Resiliência: `dotnet-httpclient-resilience`.

## Escolher a tecnologia (oficial)
- **Azure Service Bus**: mensageria que exige **transações, ordenação, sessões, dead-letter**; indicado para produção de alta escala. **Event Grid**: notificações **push** orientadas a evento (mudanças de estado de recursos Azure). **Event Hubs**: **streaming** de alto volume (telemetria, logs), modelo de log com *consumer groups*, não é pub/sub tradicional. Outras: Redis, RabbitMQ, Kafka.
- **RabbitMQ** é *broker transport* de mais baixo nível que Service Bus/NServiceBus/MassTransit/Brighter; para POC/dev (como o eShopOnContainers) basta; para sistemas críticos, avalie Service Bus. **Se precisar de abstrações ricas (ex.: Sagas de longa duração), use um service bus de mercado (NServiceBus, MassTransit, Brighter)** em vez de reinventar. O `IEventBus` do eShopOnContainers é **só prova de conceito** — não use como produção.
- Sua própria abstração de event bus só vale para recursos básicos; para recursos ricos use a API do produto escolhido.

## Integration events
- Servem para **sincronizar estado** entre microsserviços/sistemas externos publicando eventos fora do serviço; cada assinante tem seu handler. Um evento de integração é uma classe de dados (ex.: `ProductPriceChangedIntegrationEvent`).
- **Defina os eventos em cada microsserviço (na camada de aplicação); NÃO compartilhe uma biblioteca comum de eventos** entre serviços (acoplamento, mesmo motivo de não compartilhar modelo de domínio). Só compartilhe blocos finais (cliente do event bus) e utilitários como serializadores.
- **Consistência eventual**: transação de negócio entre serviços = série de ações, cada uma atualiza a entidade **e publica um evento**; **a transação não abrange banco e event bus ⇒ trate idempotência** (`dotnet-distributed-patterns`).

## Transactional Outbox (oficial, Architecture Center)
- **Problema:** salvar no banco e publicar na fila não são atômicos; falha de rede/broker/host entre os dois perde o evento e causa **inconsistência**.
- **Solução:** na **mesma transação do banco** grave a entidade **e o evento numa tabela outbox**; um **worker/relay** consulta a outbox, **publica no broker** e **marca como processado**. Com EF Core: um `DbContext` salva objeto + evento e confirma/reverte junto (`efcore-saving-concurrency`). O relay tem de **preservar a ordem** dos eventos (ex.: `OrderCreated` antes de `OrderUpdated`) e o consumidor deve ser **idempotente** (o relay pode publicar mais de uma vez). A doc detalha a versão Cosmos DB (transactional batch + change feed + Service Bus).
- Evite "salva e depois publica" sem outbox; evite publicar **antes** do commit.

## Padrões de consumo (oficial)
- **Competing Consumers:** fila com várias instâncias consumidoras, **cada mensagem é processada por um consumidor** (≠ pub/sub, onde **todos** recebem). Benefícios: nivelamento de carga, confiabilidade, escala; **entrega pelo menos uma vez**. Atenção: **ordem não garantida** ⇒ processamento **idempotente**; **poison messages** ⇒ dead-letter após `MaxDeliveryCount`; resultados exigem canal/armazenamento comum; particionar filas se um único queue virar gargalo.
- **Publisher-Subscriber:** use produto pronto (não construa); **tópicos** (canal por assunto) e **filtros por conteúdo**; autentique/autorize **publishers e subscribers por tópico**; criptografe em trânsito (e em repouso se sensível); canais são **unidirecionais** (para resposta use Request-Reply com canal próprio); ordem não garantida (pode haver ordem por partição/sessão, com custo de escala); **backpressure**: limite mensagens não confirmadas por assinante; correlação: **inclua correlation ID** em toda mensagem.
- **Entrega:** at-most-once (pode perder), **at-least-once (pode duplicar ⇒ idempotência)**, exactly-once (custo e depende da infraestrutura).
- **Schema evolution:** publishers e assinantes são implantados separadamente ⇒ prefira mudanças **compatíveis** (campos opcionais); assinantes **ignoram campos desconhecidos**; mudança breaking ⇒ versionar por nome de tópico (`orders.v1`/`orders.v2`) ou campo de versão no metadata.
- **Expiração e agendamento:** defina expiração na mensagem para descartar o que ficou irrelevante; `scheduled enqueue` para liberar depois. **Mensagem grande:** guarde o conteúdo fora e envie referência (**Claim Check**).
- Queue-Based Load Leveling (fila como buffer entre produtor e consumidor), Priority Queue, Sequential Convoy, Choreography existem no catálogo (ver fontes).

## Azure Service Bus no .NET (`Azure.Messaging.ServiceBus`)
- **Cliente:** `ServiceBusClient`, sender, receiver e processor são **seguros para cache e uso como singleton durante a vida da aplicação**, e **thread-safe/concorrentes**; **não** feche/dispose após cada mensagem (fechar derruba os links e a conexão, que é cara de reabrir). Descarte (`DisposeAsync`) **ao encerrar** para liberar conexões. Em ASP.NET Core, registre como singleton (ver `dotnet-dependency-injection`). Autentique com `DefaultAzureCredential`/identidade gerenciada em vez de connection string quando possível (ver `aspnet-configuration-options` para segredos). Portas AMQP 5671/5672 ou `AmqpWebSockets` (443).
- **Envio:** é sempre confirmado explicitamente pelo serviço; rejeições trazem `tracking-id` e se vale retentar. **Aguardar cada envio em sequência custa um round trip por mensagem**; para rajadas envie em **lote** (`ServiceBusMessageBatch`) ou concorrentemente com limite (ex.: `SemaphoreSlim`).
- **Recebimento — use `ServiceBusProcessor`** (`CreateProcessor`): `MaxConcurrentCalls` controla concorrência; **PeekLock** é o modo padrão (a mensagem fica travada até ser *settled*); `ReceiveAndDelete` é mais rápido mas **pode perder mensagens** e não permite transação nem dead-letter/defer.
- **Settlement:** `Complete` (sucesso), `Abandon` (libera para reentrega), `DeadLetter` (rejeita quando reprocessar não adianta), `Defer`. **Resolva a mensagem enquanto receiver e conexão estiverem abertos** (fechar antes faz o lock expirar e a mensagem ser reentregue); se o lock foi perdido, **receba de novo e reprocesse** (não tente "completar" a original). O lock padrão é **1 min** (máx. 5 min; use `RenewLock` para mais) — defina **acima do tempo normal de processamento**. A conclusão pode falhar após o trabalho feito ⇒ **idempotência**.
- **Dead-letter:** subfila para mensagens não entregáveis/ não processáveis; motivos incluem `MaxDeliveryCountExceeded` (**padrão 10** entregas) e `TTLExpiredException` (mensagens deferidas expiradas **não** vão para a DLQ). Monitore a DLQ e defina processo para inspecionar/reenviar.
- **Prefetch:** `PrefetchCount` reduz round trips, mas mensagens pré-buscadas ficam **travadas**; com lock de 60 s a doc sugere ~**20× a taxa máxima de processamento** dos receivers; ajuste com cuidado.
- **Sessões** dão FIFO garantido (`message sessions`); o `ServiceBusSessionReceiver` tem ciclo de vida da sessão (exceção à regra de singleton).
- **Tier/planejamento:** escolha o tier conforme necessidade (Premium para throughput previsível) — ver guia de performance.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Salvar no banco e publicar evento sem outbox (ou publicar antes do commit) | Alta |
| 2 | Consumidor não idempotente (at-least-once duplica) | Alta |
| 3 | Mensagem "venenosa" retentando para sempre / sem dead-letter e monitoramento da DLQ | Alta |
| 4 | Biblioteca de eventos compartilhada entre serviços / evento = entidade de banco | Média |
| 5 | `ServiceBusClient`/sender criado e descartado por mensagem | Alta |
| 6 | `Complete` depois de fechar receiver; lock menor que o tempo de processamento sem `RenewLock` | Alta |
| 7 | `ReceiveAndDelete` com dados que não podem ser perdidos | Alta |
| 8 | Assume ordem de chegada sem sessões/partição/design tolerante | Média |
| 9 | Sem correlation ID; mensagem sem versão/schema evolutivo; assinantes que falham com campos novos | Média |
| 10 | Mensagens grandes inline (usar claim check); sem TTL em mensagens perecíveis | Média |
| 11 | Sem autenticação/autorização por tópico; segredos de conexão no código | Alta |
| 12 | Construir event bus próprio para necessidades que um produto cobre (sagas, retries, outbox) | Média |
| 13 | Handler de mensagem fazendo trabalho síncrono bloqueante/sem `CancellationToken` ao encerrar o host | Média |

## Fontes oficiais
- Integration events / event bus (.NET microservices): https://learn.microsoft.com/en-us/dotnet/architecture/microservices/multi-container-microservice-net-applications/integration-event-based-microservice-communications
- Transactional Outbox (Cosmos DB): https://learn.microsoft.com/en-us/azure/architecture/databases/guide/transactional-out-box-cosmos
- Competing Consumers: https://learn.microsoft.com/en-us/azure/architecture/patterns/competing-consumers
- Publisher-Subscriber: https://learn.microsoft.com/en-us/azure/architecture/patterns/publisher-subscriber
- Queue-Based Load Leveling: https://learn.microsoft.com/en-us/azure/architecture/patterns/queue-based-load-leveling
- Claim Check: https://learn.microsoft.com/en-us/azure/architecture/patterns/claim-check
- Idempotent Consumer: https://learn.microsoft.com/en-us/azure/architecture/patterns/idempotent-consumer
- Service Bus — quickstart .NET: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-dotnet-get-started-with-queues
- Service Bus — performance: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-performance-improvements
- Service Bus — locks e settlement: https://learn.microsoft.com/en-us/azure/service-bus-messaging/message-transfers-locks-settlement
- Service Bus — dead-letter queues: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-dead-letter-queues
- Escolher entre serviços de mensagens: https://learn.microsoft.com/en-us/azure/service-bus-messaging/compare-messaging-services
