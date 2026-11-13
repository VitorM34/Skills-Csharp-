---
name: dotnet-clean-architecture
description: Estruturar e revisar uma aplicação ASP.NET Core em camadas / Clean Architecture - Application Core, Infrastructure, UI, regra de dependência, repositórios, composition root, onde ficam entidades, interfaces, services e DbContext. Use quando o usuário quiser criar um projeto do zero com camadas, revisar dependências entre projetos ou decidir onde colocar cada classe. Based on official Microsoft Learn docs (Architect Modern Web Applications with ASP.NET Core and Azure).
---

# Camadas / Clean Architecture em ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim).

## Do N-Layer tradicional à Clean Architecture
- N-Layer clássico: UI → BLL → DAL. Desvantagem citada pela doc: dependências de compilação vão de cima para baixo, então a lógica de negócio **depende de detalhes de acesso a dados**; testar exige banco.
- **Clean Architecture** (= Hexagonal / Ports-and-Adapters / Onion): inverte a dependência. O **Application Core** não depende de nada; **Infrastructure** e **UI** dependem do Core (e, idealmente, não um do outro). Abstrações (interfaces) ficam no Core; Infrastructure as implementa. Em runtime a ligação é feita por **DI**.
- Benefícios da doc: núcleo testável sem infraestrutura, trocar implementação (SQL → nuvem) e usar fakes em testes. A doc considera essa a forma mais apropriada de estruturar monolitos não triviais em ASP.NET Core.

## O que vai em cada projeto (doc)

| Projeto | Conteúdo | Referencia |
|---|---|---|
| **Application Core** | Entidades, Aggregates, Interfaces (inclusive de acesso a dados/arquivos/rede), Domain Services, Specifications, Exceptions customizadas e guard clauses, Domain events/handlers; DTOs simples quando necessário | nada |
| **Infrastructure** | `DbContext`, `Migration`s, repositórios (Repository pattern), serviços de infraestrutura (`FileLogger`, `SmtpNotifier`) que **implementam interfaces do Core** | Core |
| **UI (Web/API)** | Controllers / endpoints, Filters, Middleware, ViewModels/DTOs, `Program.cs` | Core (e Infrastructure só no composition root) |

- A UI interage com infraestrutura **estritamente por interfaces do Core**; sem `new` nem chamadas estáticas a tipos da Infrastructure.
- **Composition root** (`Program.cs`): liga implementações às interfaces. A doc admite que a UI referencie Infrastructure só por isso; limite as referências de tipo a esse ponto.
- Testes: unitários no Core (isolado); integração para Infrastructure.

```csharp
// Core
public interface ITodoRepository { Task<Todo?> GetByIdAsync(int id, CancellationToken ct); Task AddAsync(Todo t, CancellationToken ct); }

// Infrastructure
public sealed class EfTodoRepository(TodoDbContext db) : ITodoRepository { /* ... */ }

// UI / Program.cs (composition root)
builder.Services.AddDbContext<TodoDbContext>(o => o.UseSqlServer(cs));
builder.Services.AddScoped<ITodoRepository, EfTodoRepository>();
```

## Princípios de apoio (oficiais)
Separation of concerns, encapsulation, dependency inversion, explicit dependencies, SRP, DRY (sem acoplar duplicação coincidente), persistence ignorance, bounded contexts. Detalhes em `dotnet-modular-monolith`.

## Quando não complicar
Um projeto único "all-in-one" (pastas Models/Views/Controllers/Data/Services) é válido para apps pequenos; a doc avisa que cresce em "spaghetti" quando não há indicação de quem depende de quem. Evoluir para multi-projeto quando a complexidade pedir.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Core sem referência a Infrastructure, EF Core ou ASP.NET |
| 2 | Interfaces de acesso a dados no Core; implementações na Infrastructure |
| 3 | UI sem `new`/estático para tipos da Infrastructure (exceto composition root) |
| 4 | `DbContext` e migrations só na Infrastructure |
| 5 | Entidades no Core, sem dependência de persistência (PI) quando possível |
| 6 | DTOs de API na UI; entidades não vazam |
| 7 | Services de domínio no Core (regra de negócio), não nos controllers |
| 8 | Registro de DI centralizado no composition root |
| 9 | Testes unitários do Core sem banco |
| 10 | Dependências circulares ou "UI → Infrastructure" generalizada |

## Fontes oficiais
- Common web application architectures: https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures
- Architectural principles: https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/architectural-principles
- eShopOnWeb (referência): https://github.com/dotnet-architecture/eShopOnWeb
- Livro completo: https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/
