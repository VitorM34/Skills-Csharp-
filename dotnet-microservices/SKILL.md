---
name: dotnet-microservices
description: Projetar e revisar microserviços em .NET - bounded contexts, dados privados por serviço, API gateway, mensageria assíncrona, consistência eventual, resiliência, observabilidade, antipadrões. Use quando o usuário perguntar se deve usar microserviços, como dividir serviços, como serviços se comunicam ou revisar um design distribuído. Based on official Microsoft Learn (Azure Architecture Center) docs.
---

# Microserviços em .NET — projetar e revisar

Só afirmar o que a doc oficial diz (fontes no fim). Para stack específica do .NET (eShopOnContainers, gRPC, Dapr, Aspire, resiliência com Polly/`Microsoft.Extensions.Http.Resilience`) consultar as páginas indicadas antes de detalhar.

## O que é (doc)
Coleção de serviços pequenos e autônomos; cada um implementa **uma capacidade de negócio dentro de um bounded context**, tem seu próprio código-fonte, é implantável de forma independente, **persiste seus próprios dados** e se comunica por APIs bem definidas.

## Componentes típicos
- **Orquestração** (Kubernetes, Azure Container Apps).
- **API gateway:** ponto de entrada; roteia, cuida de autenticação/log/balanceamento. **Sem conhecimento de domínio** (senão vira acoplamento).
- **Mensageria** (Kafka, Azure Service Bus) para comunicação assíncrona/event-driven.
- **Observabilidade:** logs centralizados, métricas, tracing distribuído (OpenTelemetry), correlação entre serviços.
- **Dados:** cada serviço é dono do seu esquema; polyglot persistence conforme necessidade.

## Benefícios × desafios
Benefícios: agilidade/deploy independente, times pequenos, base de código pequena, tecnologia mista, isolamento de falhas (circuit breaker, mensageria assíncrona), escalabilidade independente, isolamento de dados.
Desafios: complexidade do sistema como um todo, desenvolvimento/teste com dependências, falta de governança, latência e congestionamento de rede (evite APIs "tagarelas" e cadeias longas), **integridade de dados** (sem ACID entre serviços: consistência eventual/BASE), gestão (DevOps maduro), versionamento compatível, habilidades da equipe.

## Boas práticas (doc)
- Modele serviços pelo **domínio** (DDD, bounded contexts); evite serviços excessivamente granulares.
- Descentralize; **dados privados ao serviço**; sem schema de banco compartilhado.
- Comunicação por APIs que modelam o domínio, sem vazar implementação.
- Evite acoplamento (schema compartilhado, protocolos rígidos).
- Mensageria com frameworks (MassTransit, NServiceBus) em vez de lógica própria de roteamento/retry.
- Segurança: mTLS entre serviços, RBAC, políticas no gateway; offload de cross-cutting para gateway/service mesh/Dapr.
- Alta coesão funcional e baixo acoplamento (o que muda junto, fica junto; comunicação excessiva = sinal de acoplamento).
- CI/CD com deploy independente; isole falhas com padrões de resiliência; chaos engineering; observabilidade.

## Antipadrões (doc)
Microserviços sem entender o domínio; eventos que dependem de eventos passados/futuros; **entidades de banco como eventos**; evitar duplicação de dados a todo custo (use materialized views); eventos genéricos; **bibliotecas compartilhadas entre serviços**; expor serviços direto ao consumidor (use gateway); configuração dentro do serviço; validação de token embutida em cada serviço; não abstrair tarefas comuns (Dapr).

## Quando NÃO (doc "Common web architectures")
- Monolito não decomponível em fatias independentes → separar só adiciona complexidade.
- Não precisa escalar partes isoladas → clonar a instância inteira é mais simples.
- Fronteiras naturais ainda não emergiram (MVP).
- Separar processos troca chamadas de método por comunicação assíncrona e exige event bus, retries, eventual consistency.
Alternativa: começar monolito (ver `dotnet-modular-monolith`) e extrair depois.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Cada serviço = uma capacidade de negócio / bounded context |
| 2 | Banco/schema não compartilhado entre serviços |
| 3 | Clientes falam com o gateway, não direto com serviços |
| 4 | Comunicação síncrona longa em cadeia (A→B→C…) |
| 5 | Falha parcial tratada (timeout, retry, circuit breaker); consistência eventual aceita |
| 6 | Eventos são contratos de negócio, não entidades de banco, nem genéricos |
| 7 | Sem bibliotecas de domínio compartilhadas acopladas |
| 8 | Logs correlacionados + tracing distribuído |
| 9 | Config externalizada; segurança tratada no gateway/plataforma |
| 10 | Há real necessidade (escala/time/independência) que justifique o custo |

## Fontes oficiais
- Microservices architecture style: https://learn.microsoft.com/en-us/azure/architecture/guide/architecture-styles/microservices
- Common web application architectures: https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures
- .NET Microservices e-book: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/
- Domain analysis / tactical DDD / boundaries: https://learn.microsoft.com/en-us/azure/architecture/microservices/model/domain-analysis
- Design patterns for microservices: https://learn.microsoft.com/en-us/azure/architecture/microservices/design/patterns
