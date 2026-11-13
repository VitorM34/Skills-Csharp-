---
name: dotnet-distributed-patterns
description: Projetar e revisar padrões de sistemas distribuídos e microsserviços em .NET - comunicação síncrona vs assíncrona, mensageria e integration events, CQRS, dados por serviço, consistência eventual, Saga e compensating transaction, idempotent consumer, retry, circuit breaker, API gateway/BFF, anti-corruption layer, strangler fig, materialized view. Use quando o usuário pedir design de comunicação entre serviços, consistência entre bancos, tratamento de falhas ou migração de monolito. Based on official Microsoft Learn docs (.NET Microservices guide and Azure Architecture Center patterns).
---

# Padrões de sistemas distribuídos

Só afirmar o que a doc oficial diz (fontes no fim). Visão geral e quando adotar: `dotnet-microservices` e `dotnet-modular-monolith`. DDD: `dotnet-ddd-tactical`. Resiliência HTTP: `dotnet-httpclient-resilience`.

## Comunicação
- Serviços são processos distintos: usam protocolos entre processos (HTTP, AMQP, binários). Eixos: **síncrono** (HTTP; cliente espera resposta) × **assíncrono** (mensageria/AMQP), e **receptor único** (padrão Command) × **múltiplos receptores** (publish/subscribe, event-driven; **precisa ser assíncrono**). Filosofia "**smart endpoints, dumb pipes**".
- O que importa não é a assincronia da thread, e sim integrar os serviços **de forma assíncrona mantendo a autonomia**: a doc recomenda usar **só mensageria assíncrona entre serviços internos** e HTTP **somente de clientes para o front (API Gateways + 1º nível de microsserviços)**; **evite misturar** mensagens com HTTP síncrono numa mesma interação.
- Broker **leve** (RabbitMQ, service bus em nuvem). Mensagens de **receptor único** devem ser processadas **uma vez**, mas em recuperação de falhas a mesma mensagem pode ser reenviada ⇒ **idempotência** (abaixo). Em consistência eventual via integration events, **deixe isso explícito ao usuário** (e não "imite" com SignalR/polling).

## Dados por microsserviço
- **Cada microsserviço é dono do seu modelo e dados**, acessados só por **API (REST/gRPC) ou mensageria**, **nunca por esquema compartilhado** (evoluções de schema exigiriam atualizações coordenadas e quebrariam a autonomia). Não há **transação ACID** entre serviços ⇒ **consistência eventual**. Bancos diferentes por necessidade (SQL × NoSQL).
- **Consultas que agregam dados de vários serviços:** (1) **API Gateway** de agregação (cuidado: gargalo/violação de autonomia; use vários gateways finos, ex. BFF); (2) **CQRS com tabelas de leitura / Materialized View** (tabela somente leitura denormalizada, **preparada de antemão** com dados de vários serviços, no formato que o cliente precisa). A doc lista mais soluções na página *Distributed data management*. Não faça join entre bancos de serviços.
- Fronteiras: ver `dotnet-ddd-tactical` (bounded contexts).

## CQRS (Azure Architecture Center)
- Separa **commands** (escrita) de **queries** (leitura). Resolve **descompasso de dados** (leitura × escrita têm formatos diferentes) e **problemas de desempenho** de consultas complexas. Commands devem representar **tarefas de negócio** ("Reservar quarto"), não updates de baixo nível; considere processá-los **assincronamente em fila**. **Queries nunca alteram dados** e retornam **DTOs** sem lógica de domínio.
- Modelos separados em **um único datastore** ou em **datastores separados** (com custo de sincronização/consistência eventual); ORMs não geram código CQRS automaticamente. Use quando há clara separação de leituras/escritas; para CRUD simples só adiciona complexidade.

## Consistência e falhas
- **Saga**: sequência de transações locais coordenada, com **transações compensatórias**: tipos: compensáveis, **pivot** (ponto sem retorno), **retryable** (após o pivot; **idempotentes**). Implementações: **Choreography** (cada serviço reage a eventos; simples para poucos serviços, mas fluxo confuso, risco de dependência cíclica, teste de integração difícil) × **Orchestration** (coordenador central; melhor para fluxos complexos; exige lógica de coordenação). Atenção: mudanças locais **não são revertidas por rollback** (compense), trate falhas transitórias e **idempotência**.
- **Compensating transaction**: desfaz o efeito de passos concluídos quando um passo falha **sem sobrescrever** mudanças concorrentes (é específico da aplicação; registre cada passo e como desfazê-lo; use um workflow que "rebobina").
- **Idempotent Consumer**: brokers (Service Bus, Event Hubs, Kafka, RabbitMQ) garantem **at-least-once** ⇒ **duplicatas acontecem**; exactly-once ponta a ponta é impraticável. Faça o **consumidor idempotente**: escolha uma **chave de deduplicação estável** (id da mensagem do produtor ou chave de idempotência de negócio; **não** `CorrelationId`, nem IDs regerados na reentrega, nem timestamps de recebimento) e **grave a marca de processado e os efeitos colaterais na MESMA transação** (atômico).
- **Retry**: falhas **transitórias** na nuvem são esperadas; estratégias: **cancelar** (se não é transitória), **retry com atraso** (a doc diz que o intervalo deve **espalhar as requisições das várias instâncias** o mais uniformemente possível, com atrasos crescentes de forma incremental ou exponencial; a palavra "jitter" **não** aparece na página do padrão Retry), com limite de tentativas; **envolva todo acesso remoto** com política; falha das tentativas vira exceção. Logue falhas iniciais como **informação** e só a **última** como erro. Para operações não críticas, **falhar rápido** pode ser melhor. Retries em operações **não idempotentes** são perigosos (ver HTTP).
- **Circuit Breaker**: bloqueia temporariamente chamadas a um recurso após atingir limiar de falhas (**Closed → Open → Half-Open**), para o recurso se recuperar e para falhar rápido; **propósito diferente do Retry** (Retry tenta de novo esperando sucesso; Circuit Breaker evita executar o que provavelmente falha); podem ser **combinados** (retry chamando via circuit breaker). Contador de falhas do estado fechado é baseado em tempo.
- Também no catálogo: Bulkhead, Throttling, Rate limiting, Queue-based load leveling, Competing consumers, Health endpoint monitoring (ver `aspnet-health-checks`, `aspnet-rate-limiting`).

## Gateway
- **Chamada direta cliente→microsserviço** gera: muitos roundtrips (latência), segurança/cross-cutting em cada serviço, protocolos internos (AMQP/binário) inacessíveis ao cliente. **API Gateway** (camada de indireção): agregação, offloading (autenticação, TLS, logging), roteamento; **vários gateways finos** para evitar um gateway monolítico (o catálogo cita o padrão *Backends for Frontends*; consulte antes de detalhar); **não ponha conhecimento de domínio no gateway**; evite que vire gargalo/ponto único (vários gateways finos).

## Migração e integração
- **Strangler Fig**: migra **incrementalmente** funcionalidades do legado para o novo sistema, roteando as requisições (façade) até aposentar o legado; reduz risco; planeje como componentes não modificáveis alcançam os novos serviços.
- **Anti-Corruption Layer**: fachada/adaptador **traduz** entre subsistemas com semânticas diferentes (modelo legado "não contamina" o novo); sem regras de negócio nem orquestração na camada; é mais um serviço a manter.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Serviços compartilhando banco/esquema | Alta |
| 2 | Cadeias longas de chamadas HTTP síncronas entre serviços internos | Alta |
| 3 | Transação distribuída assumida (2PC) em vez de saga/compensação | Alta |
| 4 | Consumidor de mensagem não idempotente; dedup sem atomicidade com o efeito | Alta |
| 5 | Evento publicado antes do commit / evento = entidade de banco | Alta |
| 6 | Retry em operação não idempotente, sem limite de tentativas nem atraso crescente/espalhado entre instâncias; sem circuit breaker em dependência instável | Alta |
| 7 | Gateway com lógica de domínio / único gateway gigante | Média |
| 8 | Agregação de dados feita por joins entre bancos em vez de materialized view/API | Média |
| 9 | CQRS aplicado a CRUD simples; commands como "set de campos" | Média |
| 10 | Migração big-bang quando strangler fig cabe; legado vazando para o modelo novo (sem ACL) | Média |

## Fontes oficiais
- Comunicação em microsserviços: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/architect-microservice-container-applications/communication-in-microservice-architecture
- Mensageria assíncrona: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/architect-microservice-container-applications/asynchronous-message-based-communication
- Data sovereignty per microservice: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/architect-microservice-container-applications/data-sovereignty-per-microservice
- Distributed data management: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/architect-microservice-container-applications/distributed-data-management
- API gateway × direto: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/architect-microservice-container-applications/direct-client-to-microservice-communication-versus-the-api-gateway-pattern
- CQRS (e-book): https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/apply-simplified-microservice-cqrs-ddd-patterns
- CQRS (Azure): https://learn.microsoft.com/en-us/azure/architecture/patterns/cqrs
- Saga: https://learn.microsoft.com/en-us/azure/architecture/patterns/saga
- Compensating transaction: https://learn.microsoft.com/en-us/azure/architecture/patterns/compensating-transaction
- Idempotent consumer: https://learn.microsoft.com/en-us/azure/architecture/patterns/idempotent-consumer
- Retry: https://learn.microsoft.com/en-us/azure/architecture/patterns/retry
- Circuit breaker: https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker
- Strangler Fig: https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig
- Anti-Corruption Layer: https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer
- Catálogo de padrões: https://learn.microsoft.com/en-us/azure/architecture/patterns/
