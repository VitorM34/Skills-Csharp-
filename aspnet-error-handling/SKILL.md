---
name: aspnet-error-handling
description: Implementar e revisar tratamento de erros em APIs ASP.NET Core - ProblemDetails (RFC 7807/9457), AddProblemDetails, UseExceptionHandler, UseStatusCodePages, Developer Exception Page, IProblemDetailsService, validação 400, respostas de erro em Minimal APIs e Controllers. Use quando o usuário pedir para padronizar erros da API, configurar handler global de exceções ou revisar respostas 4xx/5xx. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Tratamento de erros em APIs ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim).

## Configuração recomendada (Minimal APIs e Controllers)

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddProblemDetails();
// builder.Services.AddControllers();   // se usar controllers

var app = builder.Build();
app.UseExceptionHandler();   // exceções não tratadas -> ProblemDetails
app.UseStatusCodePages();    // 4xx/5xx sem corpo -> ProblemDetails
// app.MapControllers();
app.Run();
```

`AddProblemDetails` registra o `IProblemDetailsService` padrão. Com ele, geram problem details: `ExceptionHandlerMiddleware` (quando não há handler customizado), `StatusCodePagesMiddleware`, `DeveloperExceptionPageMiddleware` (em Development, quando `Accept` não inclui `text/html`). Só para respostas **sem corpo ainda**. O writer padrão atende `application/json`, `application/problem+json` e curingas; outros media types (`application/xml`, `text/html`) caem no **fallback** (trate com `TryWriteAsync` e resposta própria).

## Regras da documentação
1. **Developer Exception Page:** ligada por padrão em `Development` (templates com `WebApplication.CreateBuilder`). **Nunca** habilitar fora de Development (vaza stack trace, headers, cookies). Não garante informação: use logging.
2. **Produção:** `UseExceptionHandler` (middleware) para produzir payload de erro.
   - Controllers: `app.UseExceptionHandler("/error")` + action `[Route("/error")] public IActionResult HandleError() => Problem();`. **Não** coloque atributo de verbo (`HttpGet`) nessa action. Em OpenAPI, `[ApiExplorerSettings(IgnoreApi = true)]`. Permita acesso anônimo se necessário.
   - Minimal: `app.UseExceptionHandler(h => h.Run(async ctx => await Results.Problem().ExecuteAsync(ctx)))` ou apenas `AddProblemDetails` + `UseExceptionHandler()`.
3. **Erros de cliente/servidor sem corpo** (`Results.BadRequest()` sem body): `UseStatusCodePages()` preenche o corpo (inclui 404 de rota).
4. **Controllers:** MVC converte resultado ≥ 400 em `ProblemDetails`; validação falha → `ValidationProblemDetails`. Personalização:
   - `AddProblemDetails(o => o.CustomizeProblemDetails = ctx => {...})`
   - registrar `ProblemDetailsFactory` customizada
   - `ConfigureApiBehaviorOptions(o => o.ClientErrorMapping[404].Link = "...")`
   - `InvalidModelStateResponseFactory` para formato de validação.
5. **`IExceptionHandler`** (tratamento central de exceções conhecidas):
   - interface com um método `TryHandleAsync(HttpContext, Exception, ...)`; retorne `true` para dizer que tratou (para a cadeia), `false` para passar ao próximo/ao comportamento padrão;
   - registre com `builder.Services.AddExceptionHandler<MeuHandler>()` (vários permitidos, chamados **na ordem de registro**; o tempo de vida da instância é **singleton**);
   - **só funciona se o middleware estiver ativo**: `app.UseExceptionHandler()` é obrigatório; sem argumentos exige um fallback (`UseExceptionHandler("/Error")`, ou `AddProblemDetails()` + `UseExceptionHandler()`, ou um handler lambda), senão lança `InvalidOperationException` na inicialização;
   - se retornar `true` sem escrever resposta/status, o resultado vira **404**; escreva a resposta completa (status + corpo, p.ex. via `IProblemDetailsService.TryWriteAsync`);
   - a partir do .NET 10, exceções tratadas (`true`) não emitem logs/métricas por padrão (configurável via `SuppressDiagnosticsCallback`).
6. **Alternativa para controllers:** exceção conhecida (`HttpResponseException`) + action filter (`IActionFilter`, `Order = int.MaxValue - 10`) que define `context.Result` e `ExceptionHandled = true`.
7. Problem Details não é o único formato, mas é o comumente usado para erros de HTTP APIs.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `AddProblemDetails()` + `UseExceptionHandler()` + `UseStatusCodePages()` configurados |
| 2 | Developer Exception Page apenas em Development |
| 3 | Mensagens de exceção/stack trace não vazam em produção |
| 4 | `try/catch` genérico em cada action retornando 500 manual → substituir por handler global |
| 5 | Erros esperados (não encontrado, validação) retornam 404/400 com ProblemDetails, não exceção |
| 6 | Handler `/error` sem atributo de verbo (controllers) |
| 7 | Clientes que pedem XML/HTML tratados no fallback |
| 8 | Erros logados (logging) com correlação (`traceId` vem no ProblemDetails) |

## Fontes oficiais
- Handle errors in ASP.NET Core APIs: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling-api
- Handle errors in ASP.NET Core (geral): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling
- Boas práticas de exceções .NET: https://learn.microsoft.com/en-us/dotnet/standard/exceptions/best-practices-for-exceptions
