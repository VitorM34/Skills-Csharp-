---
name: dotnet-ddd-tactical
description: Aplicar e revisar Domain-Driven Design tático em .NET - bounded context, entidades com comportamento (rich vs anemic), aggregates e aggregate root, value objects, validações no domínio (entidades sempre válidas), domain events vs integration events, repositório por aggregate, camadas Application/Domain/Infrastructure, ViewModels. Use quando o usuário pedir para modelar domínio complexo, revisar entidades anêmicas, criar aggregates/value objects/domain events ou repositórios. Based on official Microsoft Learn docs (.NET Microservices architecture guide, DDD-oriented microservice).
---

# DDD tático em .NET

Só afirmar o que a doc oficial diz (fontes no fim). Aviso da própria doc: **o que importa é organizar o código alinhado aos problemas de negócio com a mesma linguagem do negócio (ubiquitous language); DDD só deve ser aplicado em microsserviços/contextos realmente complexos**; regras técnicas de DDD são frequentemente vistas como obstáculo. Arquitetura em camadas: `dotnet-clean-architecture`. Modelagem EF: `efcore-advanced-mapping`. Serviços simples/CRUD: `dotnet-service-implementation`.

## Bounded context
- Um **modelo de domínio coeso por bounded context** (um microsserviço de negócio, às vezes várias *physical services* compartilhando um modelo). Delimita onde um modelo se aplica; use **Context Mapping** para explicitá-los. Termos iguais podem significar coisas diferentes em contextos diferentes (o `Buyer` do Ordering tem menos atributos que o usuário do Identity).
- **Tamanho/fronteiras:** não é "o menor possível"; é a separação **mais significativa guiada pelo domínio**: crie fronteira em torno do que precisa de **coesão** e evite **comunicação "tagarela"** entre serviços (cheiro tipo *Inappropriate Intimacy*: se dois serviços colaboram muito, provavelmente devem ser um só; um serviço que depende de outro para atender a requisição não é autônomo). Acertou se há **poucas relações fortes** entre modelos e raramente é preciso **mesclar informações** de vários modelos.

## Camadas de um microsserviço DDD (um projeto por camada)
**Application** (ex.: `Ordering.API`: orquestra, ViewModels/commands/queries), **Domain** (`Ordering.Domain`: entidades, aggregates, value objects, **interfaces de repositório**, domain events), **Infrastructure** (`Ordering.Infrastructure`: EF Core, repositórios, migrations). Cada camada só conversa com certas outras; separar em class libraries facilita impor. **Persistence ignorance**: o domínio não depende de EF/infra. **Entidades de domínio não vão para a camada de apresentação**: use **ViewModels/DTOs** (a UI pode ter dados ainda não validados; entidades devem ser sempre válidas).

## Entidades
- Definidas por **identidade e continuidade**, não só por atributos. **Devem ter comportamento**, não só dados: regras e invariantes ficam em **métodos da entidade** (adicionar item, calcular total, validar) em vez de espalhadas em services.
- **Rich domain model × anêmico:** o **modelo de domínio anêmico** (entidades só com propriedades, lógica em services) é **estilo procedural**; objetos anêmicos "não são objetos de verdade". Exceção: entidades filhas dentro de um aggregate sem lógica própria (a lógica fica na aggregate root). Em CRUD simples o custo do rico não compensa.
- Implementadas como **POCOs** sem dependência de EF; classes base próprias (`Entity`, `ValueObject`, `IAggregateRoot` marker) numa pasta *SeedWork*; marker interface é discutível como anti-padrão, mas é uma forma limpa de marcar (atributo é alternativa).

## Aggregates
Grupo de entidades e value objects tratado como **unidade de consistência transacional**: invariantes e regras do grupo são garantidos por **um único ponto de entrada, a aggregate root** (acesso de fora só pela root; consistência no fim de cada ação de negócio). Ex.: `OrderAggregate` = `Order` (root) + `OrderItem` (entidade filha) + `Address` (value object) + `OrderStatus` + `IOrderRepository`. **Referencie outros aggregates por identidade** (id), mantendo-os pequenos; consistência **entre aggregates** via **domain events** (ver abaixo).

## Value objects
- **Sem identidade**; igualdade pelos **atributos** (classe base com `Equals` por todos os valores); **imutáveis** (valores fornecidos na construção e não mudam). O exemplo de value object da doc (`Address`) usa `{ get; private set; }`. A observação sobre `private set` por causa de serialização vem da página de **domain events** (eventos tratados via fila precisam de `private set` em vez de somente leitura para o desserializador), não da de value objects.
- **Persistência com EF Core:** como **owned entity types** (EF Core 2.0+) na doc do e-book; **atualização atual (EF 8+): prefira complex types** (ver `efcore-advanced-mapping`).
- **Enumeration classes** (classe em vez de `enum`) quando o enum precisa de comportamento (doc "Enumeration classes over enum types").

## Validações no domínio
- **Entidades sempre válidas:** invariantes (ex.: quantidade positiva, nome e preço obrigatórios) são responsabilidade da entidade/root, **no construtor e nos métodos que alteram estado**; senão surgem bugs por objetos em estados que nunca deveriam existir e serviços ficam checando de novo "por precaução".
- Formas: **verificar e lançar exceção**, **Specification pattern**, **Notification pattern** (coleção de erros em vez de exceção). **Garanta que a falha não deixa o estado pela metade** (ou nada muda ou todas as mutações ocorrem).
- **Data annotations/`IValidatableObject` não validam entidades no EF Core** (servem a configuração de colunas); validações de DTO de entrada ficam na camada de aplicação/API (`aspnet-validation`).

## Domain events × integration events
- Notificações sobre algo que **acabou de acontecer**; tornam **efeitos colaterais explícitos**. **Domain events**: mensagens empurradas a um *dispatcher* (mediator em memória), **em processo e no mesmo domínio**, síncronos ou assíncronos; usados para **propagar mudanças entre aggregates do mesmo domínio** (ex.: `OrderStartedDomainEvent` cria/valida o `Buyer`). **Integration events**: propagam **transações já commitadas** para outros microsserviços/contextos/apps; **sempre assíncronos**, e só devem ocorrer **se a entidade foi persistida** (senão é como se a operação não tivesse acontecido). Garanta que **ou todas as operações do domain event concluem ou nenhuma** (como uma transação).

## Repositórios
- **Um repositório por aggregate root** (nunca por tabela); o **único canal para atualizar o banco** num microsserviço DDD; **interfaces no domínio, implementação na infraestrutura**; pode-se impor via tipo genérico restrito a `IAggregateRoot`. Facilitam testes unitários (testam seu código, não a infra) e desacoplam a tecnologia de acesso. Use **Unit of Work** (o `DbContext` já é um). Detalhes EF: `efcore-testing` (repository como test double) e `efcore-querying`.

## CQRS simplificado (doc)
Separar **commands** (mudam estado, via domínio) de **queries** (idempotentes, sem efeitos): as queries ficam **fora das restrições do DDD** (aggregates), retornam **ViewModels/DTOs** e podem usar micro-ORM (Dapper); DTOs **estáticos e explícitos são preferíveis a `dynamic`** (documentação, `ProducesResponseType`, contrato). Ver `dotnet-distributed-patterns`.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Entidades anêmicas em domínio com regras complexas (lógica em services) |
| 2 | Setters públicos permitindo estado inválido; invariantes fora da entidade |
| 3 | Acesso a entidades filhas sem passar pela aggregate root; aggregates grandes demais |
| 4 | Referência direta entre aggregates em vez de por id / consistência cross-aggregate sem eventos |
| 5 | Repositório por tabela/entidade filha; `DbContext` usado direto fora da infra |
| 6 | Domain entity exposta na API (usar ViewModel/DTO) |
| 7 | Value object com identidade/mutável; owned/complex mal escolhido |
| 8 | Integration event publicado antes do commit |
| 9 | DDD aplicado a CRUD simples (custo sem benefício) |
| 10 | Fronteiras de bounded context com comunicação excessiva entre eles |

## Fontes oficiais
- DDD-oriented microservice: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/ddd-oriented-microservice
- Domain model: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/microservice-domain-model
- Domain model com .NET (aggregates/POCOs): https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/net-core-microservice-domain-model
- Value objects: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/implement-value-objects
- Validações no domínio: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/domain-model-layer-validations
- Domain events: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/domain-events-design-implementation
- Repository / persistence layer: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/infrastructure-persistence-layer-design
- Identificar fronteiras do domínio: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/architect-microservice-container-applications/identify-microservice-domain-model-boundaries
