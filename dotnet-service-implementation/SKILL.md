---
name: dotnet-service-implementation
description: Implementar e revisar services (camada de serviço / application services / domain services) e repositórios em C#/ASP.NET Core - interface + implementação, injeção de dependência, lifetime scoped, async, uso de DbContext, mapeamento DTO, tratamento de erros, onde colocar regra de negócio. Use quando o usuário pedir para criar um service, verificar se está bem implementado ou decidir entre service e repository. Based on official Microsoft Learn docs.
---

# Services (e repositórios) — implementar e revisar

Observação honesta: a doc oficial **não define um "padrão de service layer" próprio**. As regras abaixo vêm de: Clean Architecture/camadas, princípios arquiteturais, guidelines de DI, e TAP/async. Onde algo é convenção e não doc, está marcado **[CONVENÇÃO]**.

## Onde mora cada coisa (doc: Clean Architecture)
- **Domain services** e **interfaces** (inclusive as de repositório) → Application Core.
- **Implementações que tocam infraestrutura** (EF Core, arquivos, e-mail) → Infrastructure, implementando interfaces do Core.
- **Controllers/endpoints** (UI) só orquestram HTTP: recebem DTO, chamam o service por **interface**, devolvem resultado.
- Repository pattern é a forma comum de abstrair acesso a dados (a doc cita, sem exigir). [CONVENÇÃO] Em app simples com EF Core, usar o `DbContext` direto no service é aceitável (o `DbContext` já é unit of work/repository); a doc de tutoriais usa `DbContext` direto nos endpoints.

## Como implementar
1. **Interface** pequena e coesa no Core (`IOrderService`), conforme `dotnet-interface-review`.
2. **Classe** `sealed` com dependências no **construtor primário/regular** (Explicit Dependencies):
   ```csharp
   public sealed class OrderService(IOrderRepository repo, TimeProvider clock) : IOrderService
   {
       public async Task<OrderDto?> GetAsync(Guid id, CancellationToken ct = default)
       {
           var order = await repo.GetByIdAsync(id, ct);
           return order is null ? null : OrderDto.From(order);
       }
   }
   ```
3. **Registro:** `builder.Services.AddScoped<IOrderService, OrderService>();`
   - Scoped quando usa `DbContext` (scoped). Singleton só para serviços **sem estado** custosos ou compartilhados globais e thread-safe; **nunca** singleton dependendo de scoped (captive dependency). Ver `dotnet-dependency-injection`.
4. **Async:** métodos `...Async` retornando `Task`/`Task<T>`, `CancellationToken` repassado ao EF/HTTP, sem `.Result/.Wait()`. Ver `csharp-async-await`.
5. **Dados:** entrada e saída em DTOs; entidades não saem do service para a API. Ver `dotnet-dto-review`.
6. **Erros esperados** (não encontrado, regra violada): retorno claro (nullable/resultado) ou exceção de domínio tratada por handler global → `ProblemDetails`. Ver `aspnet-error-handling`. Evite `catch` genérico que engole erro.
7. **Sem estado estático**; sem `new` de colaboradores; sem service locator (`IServiceProvider.GetService`) dentro do service.
8. **Um service = uma responsabilidade.** Muitas dependências injetadas = sinal de violar SRP (doc de DI): quebre em serviços menores.
9. **Disposable:** não descarte o que o container criou; objetos criados fora do container são seu dever.
10. **Testabilidade:** dependências por interface permitem fakes/mocks; Core testável sem banco.

## Checklist de revisão
| # | Verificar | Base |
|---|---|---|
| 1 | Service sem interface, ou interface sem consumidor/implementação | interface guidelines |
| 2 | `new` de repositório/DbContext/HttpClient dentro do service | DI guidelines |
| 3 | Lifetime errado (singleton com `DbContext`; captive dependency) | DI guidelines |
| 4 | Service chamando `IServiceProvider.GetService` | DI guidelines (service locator) |
| 5 | Métodos síncronos para I/O, `.Result`, `async void` | async docs |
| 6 | Falta `CancellationToken` em I/O | async docs |
| 7 | Retorna/recebe entidade EF na fronteira da API | DTO tutoriais |
| 8 | Regra de negócio dentro do controller/endpoint | Clean Architecture |
| 9 | Service com muitas dependências injetadas (a doc não dá número; um limite como "6+" seria CONVENÇÃO) | SRP (DI guidelines) |
| 10 | Estado mutável em campo de service singleton sem sincronização | DI guidelines (thread safety) |
| 11 | Exceções engolidas ou `throw ex;` perdendo stack | exceptions (ver `dotnet-exception-handling`) |
| 12 | Duas operações EF paralelas no mesmo contexto | EF Core DbContext doc |

## Fontes oficiais
- Common web application architectures: https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures
- Architectural principles: https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/architectural-principles
- DI guidelines: https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/guidelines
- Async scenarios: https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/async-scenarios
- DbContext lifetime: https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/
