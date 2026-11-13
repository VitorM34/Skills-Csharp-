---
name: aspnet-minimal-api
description: Implementar e revisar Minimal APIs do ASP.NET Core (WebApplication, MapGet/MapPost/MapPut/MapPatch/MapDelete, MapGroup, TypedResults vs Results, Results<T1,T2>, endpoint filters, validação com DataAnnotations, DI em handlers, WithName/OpenAPI). Use quando o usuário pedir para criar ou revisar uma API minimal, organizar endpoints em grupos ou escolher os tipos de retorno. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# ASP.NET Core Minimal APIs — implementar e revisar

Só afirmar o que a doc oficial diz (fontes no fim). Para verbos, status codes e binding comuns: `aspnet-http-endpoints`.

## Estrutura mínima

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDbContext<TodoDb>(opt => opt.UseInMemoryDatabase("TodoList"));
builder.Services.AddOpenApi();
var app = builder.Build();

if (app.Environment.IsDevelopment()) app.MapOpenApi();

var todoItems = app.MapGroup("/todoitems");
todoItems.MapGet("/", GetAllTodos);
todoItems.MapGet("/{id}", GetTodo);
todoItems.MapPost("/", CreateTodo);
todoItems.MapPut("/{id}", UpdateTodo);
todoItems.MapPatch("/{id}", PatchTodo);
todoItems.MapDelete("/{id}", DeleteTodo);
app.Run();

static async Task<IResult> GetTodo(int id, TodoDb db) =>
    await db.Todos.FindAsync(id) is Todo todo
        ? TypedResults.Ok(new TodoItemDTO(todo))
        : TypedResults.NotFound();
```
(estrutura do tutorial oficial; handler pode ser lambda, função local, método de instância ou estático, síncrono ou assíncrono.)

## Regras da documentação

1. **Verbos:** `MapGet`, `MapPost`, `MapPut`, `MapDelete`, `MapPatch`; vários verbos com `MapMethods`.
2. **`MapGroup`** define prefixo comum e aplica convenções ao grupo todo (`RequireAuthorization()`, `WithTags(...)`). Grupos aninham; filtros do grupo executam antes dos internos. Organize em métodos de extensão `MapTodosApi(this RouteGroupBuilder group)`.
3. **Retorno:** `IResult` (framework chama `ExecuteAsync`); `string` → `text/plain`; qualquer outro tipo `T` → JSON.
4. **Prefira `TypedResults` a `Results`**: testabilidade (`Assert.IsType<Ok<Todo[]>>(result)`) e metadados de resposta para OpenAPI automáticos. Para vários retornos possíveis use `Results<TResult1, TResultN>` em vez de `IResult` (mantém metadata e dá checagem em compilação).
5. **Helpers:** `Ok`, `Created`, `NoContent`, `NotFound`, `BadRequest`, `Problem`, `ValidationProblem`, `StatusCode`, `Text`, `Redirect`, `File`. Cabeçalhos via `HttpContext.Response.Headers`.
6. **Binding:** ver `aspnet-http-endpoints`. `[AsParameters]` agrupa parâmetros num tipo (binding simples, não recursivo). Binding customizado: `TryParse`, `BindAsync`, `IBindableFromHttpContext`.
7. **Validação:** baseada em `System.ComponentModel.DataAnnotations`, aplicada a parâmetros de classe/record (query, header, corpo) **somente se você chamou `builder.Services.AddValidation()`** (sem isso, nada é validado). Falha → `400` com detalhes. Desligar por endpoint: `.DisableValidation()`. Personalizar com `IProblemDetailsService`. Detalhes completos na skill `aspnet-validation`.

```csharp
public record Product([Required] string Name, [Range(1, 1000)] int Quantity);
```
8. **DI em handlers:** serviço registrado é ligado ao parâmetro sem atributo; `[FromKeyedServices("key")]` para keyed services.
9. **Nomes de endpoint:** `.WithName("hi")` (sensível a maiúsculas, único globalmente); vira operationId no OpenAPI; gere URL com `LinkGenerator`.
10. Documente respostas com `.Produces<T>(status)` quando usar `Results` (não necessário com `TypedResults`/`Results<>`).
11. **Endpoint filters** (rodam antes/depois do handler; úteis para validar parâmetros/corpo, logar, checar versão de API, inspecionar/alterar argumentos, interceptar a resposta):
    - delegate: `.AddEndpointFilter(async (ctx, next) => { var arg = ctx.GetArgument<T>(0); ...; return await next(ctx); })` (`GetArgument` pelo índice na ordem de declaração do handler);
    - classe: `IEndpointFilter.InvokeAsync(EndpointFilterInvocationContext, EndpointFilterDelegate)` e `.AddEndpointFilter<MeuFiltro>()`; o filtro pode **resolver dependências da DI no construtor**, mas o **filtro em si não é resolvido pela DI**;
    - ordem: o código **antes** de `next` roda FIFO; o **depois** de `next` roda na ordem inversa (FILO);
    - `AddEndpointFilterFactory` quando o filtro depende da assinatura do handler (`MethodInfo`);
    - também aplicável a grupos (`MapGroup(...).AddEndpointFilter(...)`) e a controllers (`MapControllers().AddEndpointFilter(...)`).
12. Migração de controllers: filtros de ação → endpoint filters ou middleware; filtros de exceção → middleware de exceção; usar `AddProblemDetails()`.

## Quando preferir controllers (doc de erros)
Validação de modelo complexa, tratamento de exceção centralizado em vários controllers, controle fino do formato de erro e integração com filtros/convenções do MVC.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Handlers retornam `TypedResults`/`Results<>` (não `Results.*` solto) |
| 2 | Endpoints agrupados com `MapGroup` e convenções (auth, tags) no grupo |
| 3 | Handlers grandes inline na `Program.cs` → mover para métodos/classes de extensão |
| 4 | DTOs de entrada/saída, não entidades (ver `dotnet-dto-review`) |
| 5 | `AddValidation()` registrado e atributos de validação nos records/classes de entrada |
| 6 | Status codes por verbo conforme `aspnet-http-endpoints` |
| 7 | `DbContext` e serviços por DI no parâmetro (nunca `new`) |
| 8 | Nomes de endpoint únicos; OpenAPI habilitado só onde pretendido (ex.: Development) |
| 9 | Handler assíncrono com `await`, sem `.Result`/`.Wait()` |
| 10 | Tratamento de erro global com ProblemDetails (ver `aspnet-error-handling`) |

## Fontes oficiais
- Minimal APIs (referência rápida): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis
- Tutorial: https://learn.microsoft.com/en-us/aspnet/core/tutorials/min-web-api
- Parameter binding: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/parameter-binding
- Respostas: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/responses
- Filtros: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/min-api-filters
- Validação: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/validation
- OpenAPI: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi
