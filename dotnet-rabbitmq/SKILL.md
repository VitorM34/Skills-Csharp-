---
name: dotnet-rabbitmq
description: Usar RabbitMQ corretamente em .NET com o cliente oficial RabbitMQ.Client 7.x (API async) - ConnectionFactory/IConnection/IChannel, ciclo de vida de conexões e canais, recuperação automática, filas durable/quorum, publicação persistente com publisher confirms e mandatory, consumo com AsyncEventingBasicConsumer, ack/nack manual, prefetch (BasicQosAsync), idempotência, dead-letter, poison messages (delivery limit), retry sem loop, heartbeats, concorrência/thread-safety de canais, segurança e checklist de produção. Use quando o usuário pedir publisher/consumer RabbitMQ, perder ou duplicar mensagens, configurar filas, ou revisar código RabbitMQ. Based on official RabbitMQ documentation (rabbitmq.com) e código do cliente .NET - fonte do projeto, não da Microsoft.
---

# RabbitMQ em .NET (cliente `RabbitMQ.Client` 7.x)

**Proveniência:** documentação **oficial do projeto RabbitMQ** (rabbitmq.com — guia da API .NET, Reliability, Confirms, Quorum Queues, DLX, Production Checklist) e o **código-fonte do cliente .NET** (confirmação de nomes de API) — **[RMQ]**. A Microsoft só cita o RabbitMQ como opção de broker (`dotnet-messaging`). **Versões:** cliente **7.x** (API 100% async; as páginas gerais de confirms ainda mostram snippets do 6.x — `IModel`/`EventingBasicConsumer` — **não use**). Recursos marcados **[4.3+]** exigem broker RabbitMQ 4.3 ou superior; **[4.0+]** exigem 4.0. Convenções minhas estão marcadas **CONVENÇÃO**.
Ligações: `dotnet-messaging` (outbox, idempotência, padrões), `dotnet-distributed-patterns`, `aspnet-hosted-services`, `dotnet-dependency-injection`, `aspnet-health-checks`, `aspnet-logging`, `dotnet-observability`, `dotnet-local-dev-containers`.

## Tipos principais [RMQ]
`ConnectionFactory` (cria conexões), `IConnection`, `IChannel` (operações do protocolo), `IAsyncBasicConsumer` / `AsyncEventingBasicConsumer` (evento `ReceivedAsync`), `BasicProperties`, namespaces `RabbitMQ.Client.Events` e `...Exceptions`. Pacote NuGet `RabbitMQ.Client`. Limitação: `ulong` não é suportado em headers. Métodos (confirmados no código do cliente): `CreateConnectionAsync`, `CreateChannelAsync`, `QueueDeclareAsync`, `ExchangeDeclareAsync`, `QueueBindAsync`, `BasicPublishAsync`, `BasicConsumeAsync`, `BasicAckAsync`, `BasicNackAsync`, `BasicRejectAsync`, `BasicQosAsync`, `BasicCancelAsync`, `BasicGetAsync`, `GetNextPublishSequenceNumberAsync`, `CloseAsync`.

## Conexão
- **Conexões são feitas para durar**: abrir uma por operação (ex.: por mensagem) é **"fortemente desaconselhado"** (muitos round trips). Abra na inicialização e reutilize. **CONVENÇÃO:** registre a `IConnection` como **singleton** (criada uma vez de forma assíncrona no startup/hosted service) e descarte no shutdown.
- `new ConnectionFactory { HostName, UserName, Password, VirtualHost }` ou `factory.Uri = new Uri("amqp://user:pass@host:port/vhost")` (o .NET exige host e não aceita vhost vazio na URI); `await factory.CreateConnectionAsync()`. Padrões: `guest/guest`, vhost `/`, `localhost`, porta **5672** (**5671 com TLS**). O usuário **`guest` só conecta de localhost**; em produção **delete o `guest`** e crie usuários próprios. **Segredos** de conexão fora do código (`aspnet-configuration-options`, `aspnet-identity-data-protection`).
- **`ClientProvidedName`** (ex.: `"app:orders component:consumer"`) aparece nos logs e na UI de management — "fortemente recomendado".
- **Lista de endpoints** (`CreateConnectionAsync(IEnumerable<AmqpTcpEndpoint>)`) tenta o primeiro alcançável (cluster).
- **Falha na conexão inicial NÃO dispara recuperação automática**: você implementa retry (ex.: captura `BrokerUnreachableException`, espera e tenta de novo, com limite e log).
- **Recuperação automática** de rede: reconecta, reabre canais e restaura `basic.qos`, confirms e transações, e depois a **topologia** (exchanges, queues, bindings, **consumers**). No código do 7.x `AutomaticRecoveryEnabled` e `TopologyRecoveryEnabled` já são `true` por padrão; `NetworkRecoveryInterval` padrão **5 s**. Dispara por I/O exception, timeout de leitura ou heartbeats perdidos. **Não** recupera quando você fecha com `CloseAsync`, nem em exceção de canal (indica erro semântico). **Com topology recovery ligado, não recrie consumers/topologia manualmente** — registrar o mesmo consumer tag que já foi restaurado é erro de protocolo e pode gerar **loop infinito de recuperação**.
- **Publicações com a conexão caída são rejeitadas com exceção — o cliente não as bufferiza e mensagens escritas antes da detecção podem se perder**; só **publisher confirms** garantem entrega. ⇒ trate a falha (retry/outbox — `dotnet-messaging`).
- Eventos úteis em `IConnection`: `ConnectionShutdownAsync`, `RecoverySucceededAsync`, `ConnectionRecoveryErrorAsync`, `CallbackExceptionAsync` → logue.

## Canais e threads
- Canais também são de longa duração, mas **erros de canal o fecham** (ex.: consumir de fila inexistente, publicar em exchange inexistente) ⇒ o canal fechado não serve mais; abra outro. Em dúvida, **reuse o canal**.
- **`IChannel` não deve ser usado por várias threads ao mesmo tempo. Para publicação isto é "requisito rígido"**: compartilhar canal em publish concorrente causa intercalação incorreta de frames (connection-level exception, erros "unexpected frame" no log do servidor, ou exceções de pipelining). Use **um canal por publisher/thread** ou **exclusão mútua** (ex.: `SemaphoreSlim` em volta do `BasicPublishAsync`). Consumers concorrentes/TPL que compartilham o canal precisam de exclusão mútua nas **confirmações (acks)**.
- Callbacks de consumer são **sequenciais por padrão** (`ConsumerDispatchConcurrency = 1`); aumente para despachar em paralelo. Na mesma canal a **ordem de despacho é preservada**, mas com concorrência > 1 o processamento pode ser paralelo e causar condições de corrida; **com concorrência > 1 confirme uma entrega por vez** (ack múltiplo pode virar *double acknowledgement*, erro de protocolo). Dentro do handler pode-se chamar operações do mesmo canal sem deadlock.

## Topologia
- Declarar é idempotente (cria se não existir). **Exchange/queue "não durable" somem no restart**: para dados importantes use **filas duráveis** (ou tipos replicados) **e mensagens persistentes**.
- **Quorum queues** (`x-queue-type: quorum`, `durable: true`) são o tipo recomendado para filas **críticas e de longa vida** (ex.: pedidos recebidos); **não** valem para filas transitórias, RPC reply, mensageria de chat/ticker; para fan-out com leituras repetíveis use **streams**; mais de ~5000 quorum queues merece revisão da topologia. Não suportam filas não-durable, exclusivas nem *global QoS*. O exemplo oficial de work queue declara `x-queue-type = quorum`.
- Propriedades de fila devem ser iguais em toda re-declaração (senão erro `PRECONDITION_FAILED`). **Prefira policies** (DLX, TTL, limites, delivery-limit) a `x-arguments` fixos no código — policies mudam sem redeploy; se ambos definem DLX, o **argumento vence** a policy. Um *default queue type* pode ser configurado por vhost.
- *Passive declare* verifica existência (falha fecha o canal ⇒ use canal descartável). Mensagens não roteáveis: `mandatory` + `BasicReturnAsync`, ou **alternate exchange**.
- Ordem das mensagens: só é garantida com cuidado — um stream ou fila com **single active consumer**; com vários consumers/requeue a ordem pode mudar.

## Publicar com segurança
```csharp
var channelOpts = new CreateChannelOptions(
    publisherConfirmationsEnabled: true,
    publisherConfirmationTrackingEnabled: true,
    outstandingPublisherConfirmationsRateLimiter: new ThrottlingRateLimiter(256)); // limite de confirmações pendentes
await using var channel = await connection.CreateChannelAsync(channelOpts);

var props = new BasicProperties { Persistent = true /* ContentType, MessageId, CorrelationId... */ };
// com tracking ligado, o await só retorna quando o broker CONFIRMA; nack ou retorno (mandatory) lançam exceção
await channel.BasicPublishAsync(exchange, routingKey, mandatory: true, basicProperties: props, body: bytes);
```
(Exemplo derivado do tutorial oficial *Publisher Confirms* do cliente 7.x.)
- **Persistência:** mensagem **persistente** (`Persistent`/`DeliveryMode=2`) em fila **durable** para sobreviver a restart do broker.
- **Publisher confirms** são extensão do RabbitMQ (não vêm ligados): confirmação para mensagem persistente em fila durable = **persistida em disco**; em quorum queue = **aceita por um quorum de réplicas**; a confirmação é assíncrona e sem garantia de tempo; **nack** só ocorre em erro interno da fila. Tutorial oficial: 3 estratégias — **individual** (mais simples, mais lenta), **em lotes** (aguarda um lote; a doc usa metade do limite de pendências), **assíncrona** com callbacks `BasicAcksAsync`/`BasicNacksAsync`/`BasicReturnAsync` e `GetNextPublishSequenceNumberAsync` para rastrear. Transações do AMQP reduzem o throughput ~250×; use confirms.
- Para mensagens **não roteáveis**: o broker confirma depois de verificar que não roteia; com `mandatory`, o `basic.return` chega **antes** do ack.
- **Reenvio após falha ⇒ pode duplicar** (a confirmação pode ter se perdido) ⇒ consumidores **idempotentes** (`dotnet-messaging`). Publicar a partir do banco: **outbox**.
- `Expiration` (TTL por mensagem em ms, string) existe em `BasicProperties`; `Headers` para metadados.

## Consumir com segurança
```csharp
await channel.BasicQosAsync(prefetchSize: 0, prefetchCount: 50 /* ajuste */, global: false);
var consumer = new AsyncEventingBasicConsumer(channel);
consumer.ReceivedAsync += async (_, ea) =>
{
    var body = ea.Body.ToArray();          // COPIAR/desserializar antes de o handler retornar
    try
    {
        await ProcessAsync(body, ea);      // idempotente
        await channel.BasicAckAsync(ea.DeliveryTag, multiple: false);
    }
    catch (PermanentFailureException)      // erro que não adianta repetir (poison)
    {
        await channel.BasicNackAsync(ea.DeliveryTag, multiple: false, requeue: false); // vai ao DLX (se houver)
    }
    // falha TRANSITÓRIA: não dê requeue imediato em loop — use retry com atraso (ver "Poison messages, DLX e retry")
};
await channel.BasicConsumeAsync("orders", autoAck: false, consumer: consumer);
```
(Estrutura do worker oficial; o bloco `catch` é exemplo — a decisão requeue × DLX segue as regras abaixo.)
- **Payload é `ReadOnlyMemory<byte>`**: "**deve ser desserializado ou copiado antes de o handler retornar**" — guardar a referência é inseguro (a memória pode ser liberada a qualquer momento).
- **Ack manual (`autoAck: false`)**: ack = "processado"; **auto-ack é inseguro** (mensagem perdida se conexão/canal cai antes do processamento) e sem limite de pendências pode **estourar a memória** do consumidor — só para consumidores rápidos e estáveis. **Confirme depois de fazer o trabalho** (efeitos já aplicados).
- **Redelivery:** deliveries sem ack voltam à fila quando o canal/conexão fecha, e levam a flag **`redelivered`** (dica de que pode ter sido vista; se **não** está setada, nunca foi vista) ⇒ projete para **idempotência** (a doc prefere idempotência a deduplicar explicitamente; pode checar duplicata só quando `redelivered`).
- **`nack`/`reject`:** `requeue: true` recoloca na fila; `requeue: false` envia ao **DLX** (se configurado) ou descarta. `nack` permite `multiple`; `reject` não. **Se todos os consumers dão requeue por falha transitória, cria-se um loop requeue/redelivery** caro (rede/CPU): conte redeliveries e descarte de vez ou agende re-fila com atraso.
- **Prefetch (`BasicQosAsync`):** limita entregas sem ack por canal (janela deslizante). Valores **100–300** costumam dar boa vazão sem risco de sobrecarregar; **1** é o mais conservador e reduz muito o throughput (principalmente com latência alta); `0` = ilimitado (cuidado). Quorum queues limitam o prefetch máximo a **2000**. Ack de vários de uma vez libera mais entregas.
- **Timeout de ack:** o broker aplica timeout de confirmação (**padrão 30 min**; configurável `consumer_timeout`); estourou ⇒ o canal é fechado com `PRECONDITION_FAILED` e as mensagens voltam. **[4.3+]** suportado só por quorum queues, com `x-consumer-timeout` por consumer/fila/policy. Trabalho longo precisa caber no timeout ou ser dividido.
- **`BasicGetAsync` (polling) é "muito ineficiente" e desencorajado** — use push (`BasicConsumeAsync`).
- Cancelamento do consumer pelo servidor (fila apagada/failover): trate `HandleBasicCancel`/shutdown e re-consuma.

## Poison messages, DLX e retry
- **Dead-lettering** acontece quando: (1) `reject`/`nack` com `requeue=false`; (2) TTL por mensagem expira; (3) fila excede o limite de tamanho; (4) quorum queue excede o **delivery limit**. Se a **fila inteira** expira, as mensagens **não** são dead-lettered. Configure `dead-letter-exchange` **por policy**.
- **Quorum queue — delivery limit [4.0+]:** padrão **20** (antes ilimitado; `-1` desliga, não recomendado). O contador vem no header **`x-delivery-count`**; a mensagem que passa do limite é descartada ou **dead-lettered**. **Recomendação oficial: toda quorum queue deve ter dead-letter configurado** (para não perder mensagens sem querer; um *stream* serve como DLQ barata e retém por um tempo). `basic.reject` e crash/perda de conexão incrementam o `delivery-count`; **`basic.nack` e timeout de consumer não** [com 4.3 a regra do limite é baseada em `delivery-count`, e há o header `x-acquired-count`].
- **Retry com atraso [4.3+]:** *delayed retry* nas quorum queues segura mensagens devolvidas com **back-off linear** (`delay = min(min_delay × delivery_count, max_delay)`), recomendado em vez de depender do delivery limit ou de loops. A alternativa clássica é o **dead-letter cycle** (DLX + fila de espera com TTL), mas a doc recomenda o delayed retry; o broker detecta ciclos e **descarta a mensagem se não houve rejeição no ciclo**.
- No consumidor: classifique erros — **transitório** ⇒ retry com atraso (limitado); **permanente/poison** ⇒ `reject/nack requeue:false` (DLX). Sempre registre o motivo e monitore a DLQ (`dotnet-messaging`).

## Heartbeats, bloqueio e operação
- **Heartbeats:** padrão sugerido **60 s**; detectam conexões TCP mortas (sem eles, pode levar ~11 min); **não** desative nem use valores muito baixos (falsos positivos). Em .NET: `ConnectionFactory.RequestedHeartbeat`.
- **Conexão bloqueada:** alarmes de recurso (memória/disco) fazem o broker **bloquear publishers** (notificações connection.blocked/unblocked) — projete para tolerar backpressure.
- **Produção (checklist oficial):** armazenamento durável; vhosts separados por tenant/ambiente; **usuários dedicados sem `guest`**; permissões mínimas; **TLS**; monitoramento e métricas desde o início; memória/disco/file handles com folga (quorum queues usam mais); importar definições (usuários/vhosts/topologia) por **definitions**.
- **Health check** do broker no ASP.NET Core: pacote de terceiros `AspNetCore.Diagnostics.HealthChecks` (não é da Microsoft — ver `aspnet-health-checks`).

## Encaixe na aplicação .NET (CONVENÇÃO)
- **Consumer como `BackgroundService`** (`aspnet-hosted-services`): abrir canal/consumir em `ExecuteAsync`/`StartAsync`; no shutdown, **cancelar o consumer (`BasicCancelAsync`), aguardar o processamento em andamento, confirmar e só então fechar canal/conexão** (`CloseAsync`). Use `IServiceScopeFactory` para criar escopo **por mensagem** (DbContext é scoped — `dotnet-dependency-injection`, `efcore-saving-concurrency`).
- **Logs/telemetria:** logue `MessageId`/`CorrelationId`/`x-delivery-count`/`redelivered` (`aspnet-logging`, `dotnet-observability`); propague correlation ID nos headers.
- **Alternativas de alto nível** (retry, saga, outbox prontos): MassTransit, NServiceBus, Brighter (citados pela Microsoft em `dotnet-messaging`) — avalie antes de reescrever essas funções à mão.
- Teste com broker real via container (`dotnet-local-dev-containers`, `dotnet-integration-testing`).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Conexão/canal criado e fechado por mensagem | Alta |
| 2 | Canal compartilhado entre threads publicando sem exclusão mútua | Alta |
| 3 | Publicação sem publisher confirms / sem `mandatory` / sem tratar nack e retorno; fila ou mensagem não durable/persistente em dado importante | Alta |
| 4 | `autoAck: true` em processamento que não pode perder mensagem; sem prefetch (0) | Alta |
| 5 | Ack antes de concluir o trabalho; ack/nack em canal fechado; sem tratamento de exceção no handler | Alta |
| 6 | Consumidor não idempotente (redelivery/duplicata inevitáveis) | Alta |
| 7 | Requeue infinito de falha permanente (loop); quorum queue sem DLX/limite; DLQ sem monitoramento | Alta |
| 8 | Guardar `ea.Body` (referência) fora do handler sem copiar | Alta |
| 9 | Recriar consumers/topologia manualmente com topology recovery ligado; sem retry na conexão inicial | Média |
| 10 | Usuário `guest`/credenciais no código; sem TLS; sem `ClientProvidedName`; heartbeat desligado/muito baixo | Média |
| 11 | `x-arguments` fixos no código em vez de policies; propriedades de fila divergentes | Média |
| 12 | Quorum queue usada para filas transitórias/RPC; ordem assumida sem single active consumer | Média |
| 13 | Handler longo que estoura o timeout de ack (30 min padrão); shutdown sem drenar mensagens em andamento | Média |
| 14 | Uso do exemplo antigo (`IModel`, `EventingBasicConsumer`, API síncrona) com cliente 7.x | Média |

## Fontes [RMQ] (documentação oficial do RabbitMQ)
- .NET/C# Client API Guide: https://www.rabbitmq.com/client-libraries/dotnet-api-guide
- Cliente .NET (visão geral): https://www.rabbitmq.com/client-libraries/dotnet
- Consumer Acknowledgements and Publisher Confirms: https://www.rabbitmq.com/docs/confirms
- Reliability Guide: https://www.rabbitmq.com/docs/reliability
- Publishers: https://www.rabbitmq.com/docs/publishers
- Consumers (timeout de ack): https://www.rabbitmq.com/docs/consumers
- Queues: https://www.rabbitmq.com/docs/queues
- Quorum Queues (poison messages, delivery limit, delayed retry): https://www.rabbitmq.com/docs/quorum-queues
- Dead Letter Exchanges: https://www.rabbitmq.com/docs/dlx
- Heartbeats: https://www.rabbitmq.com/docs/heartbeats
- Production Deployment Guidelines: https://www.rabbitmq.com/docs/production-checklist
- Tutoriais .NET (Work Queues, Publisher Confirms): https://www.rabbitmq.com/tutorials/tutorial-two-dotnet · https://www.rabbitmq.com/tutorials/tutorial-seven-dotnet
- Código-fonte do cliente .NET: https://github.com/rabbitmq/rabbitmq-dotnet-client
