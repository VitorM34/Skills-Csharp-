---
name: aspnet-middleware-pipeline
description: Implementar e revisar o pipeline de middleware do ASP.NET Core - ordem de UseExceptionHandler/UseHttpsRedirection/UseRouting/UseCors/UseAuthentication/UseAuthorization, Use/Run/Map, curto-circuito, middleware customizado (convenção vs IMiddleware), dependências por requisição, ambientes (Development/Production), roteamento e endpoints. Use quando o usuário pedir para criar middleware, revisar a ordem do Program.cs ou entender por que um middleware não executa. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Pipeline de middleware, roteamento e ambientes — ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Autenticação/autorização: `aspnet-authentication-authorization`. Erros: `aspnet-error-handling`.

## Conceito
Middleware = componente do pipeline que trata request/response. Cada um **decide se passa ao próximo** e pode executar trabalho **antes e depois** do `next`. Delegates configurados com `Use` (encadeia, recebe `next`), `Run` (**terminal**, sem `next`; qualquer `Use/Run` depois do primeiro `Run` nunca executa) e `Map` (ramifica por prefixo de caminho). Ordem de entrada = ordem no `Program.cs`; a resposta volta na **ordem inversa**. **Curto-circuito** evita trabalho desnecessário (ex.: arquivos estáticos). Blazor WebAssembly standalone não tem pipeline de servidor.

```csharp
app.Use(async (context, next) =>
{
    // trabalho que pode escrever na resposta
    await next.Invoke(context);
    // trabalho que NÃO deve escrever na resposta
});
```
Regras: **não chame `next` depois que a resposta começou** e não altere status/headers depois que o corpo começou (lança exceção); escrever no corpo depois de `next` pode violar `Content-Length` ou corromper o formato. Cheque `Response.HasStarted`.

## Ordem recomendada (doc "Middleware order")
1. Exceção/erro: **Development** → `UseDeveloperExceptionPage` (e `UseDatabaseErrorPage`); **Production** → `UseExceptionHandler` + `UseHsts`. Handlers de exceção entram **cedo** para capturar exceções dos seguintes.
2. `UseHttpsRedirection`
3. `UseStaticFiles` (se necessário; curto-circuita) / `MapStaticAssets`
4. `UseCookiePolicy` (GDPR)
5. `UseRouting` (se não for chamado, roda no início por padrão; `WebApplication` já envolve o pipeline com `UseRouting`/`UseEndpoints` e normalmente não precisa chamá-los)
6. `UseRateLimiter` (se usar `[EnableRateLimiting]`/limites por endpoint, **depois** de `UseRouting`; só limitadores globais podem vir antes)
7. `UseRequestLocalization` (**antes** de qualquer middleware que leia a cultura, ex.: `UseStaticFiles`)
8. `UseCors` → `UseAuthentication` → `UseAuthorization` (**nessa ordem**); `UseCors` **antes** de `UseResponseCaching`
9. `UseAntiforgery` (**depois** de `UseAuthentication` e `UseAuthorization`)
10. `UseSession` (depois de cookie policy, antes de Razor Pages/MVC)
11. `UseResponseCompression`/caching (a ordem entre cache e compressão depende do app: cachear a resposta comprimida economiza CPU mas pode guardar várias representações Gzip/Brotli)
12. Endpoints: `MapRazorComponents`, `MapRazorPages`, `MapControllers`/`MapControllerRoute`, `MapGet`...
Autenticação **não** curto-circuita requisições não autenticadas; a rejeição vem na autorização, depois que o endpoint é selecionado.

## Escrever middleware
**Por convenção (classe):** construtor recebe `RequestDelegate next` e dependências; método **público `Invoke`/`InvokeAsync`**, retornando `Task`, primeiro parâmetro `HttpContext`. Prefira o overload `InvokeAsync(HttpContext)` (economiza 2 alocações por requisição). O middleware é **construído uma vez** por vida da aplicação: injete no construtor só dependências singleton (Explicit Dependencies Principle); **serviços scoped/por-requisição vão como parâmetros de `InvokeAsync`** (populados por DI). Exponha com um método de extensão `UseMeuMiddleware(this IApplicationBuilder)`.

**Por fábrica (`IMiddleware`):** `UseMiddleware` resolve via `IMiddlewareFactory` se o tipo implementa `IMiddleware`; o middleware é registrado no container como **scoped ou transient** (ativação por requisição, dependências scoped no construtor). Use quando precisa de dependências scoped no construtor ou de controle de lifetime.

```csharp
public class RequestCultureMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, IMyScopedService svc)   // scoped via parâmetro
    {
        // ...
        await next(context);
    }
}
```

## Roteamento (doc "Routing")
- Roteamento por **endpoints**: `UseRouting` seleciona o endpoint e o anexa ao `HttpContext`; o endpoint é `null` antes de `UseRouting`; middleware **depois** de `UseEndpoints` só roda se nada casou. Endpoints são imutáveis e sempre **terminais**.
- **Metadata de endpoint** (ex.: política de autorização, `[RequiresAudit]`) permite middleware por endpoint no padrão *opt-in*.
- Prefira roteamento a middleware terminal customizado: terminal com `UseAuthorization`/`UseCors` exige integração manual; ao mapear, devolva o builder do endpoint para aplicar políticas.
- Correspondência: todas as correspondências possíveis são processadas ao mesmo tempo (sem ordem garantida); desempate por **precedência do template** e só então `RouteEndpoint.Order` (use apenas para evitar ambiguidade). Catch-all é o menos específico. `MapControllerRoute` atribui `Order` pela ordem de chamada.
- Restrições (`{id:int}`, `:alpha`); geração de URL com `LinkGenerator` (`GetPath*` caminho absoluto, `GetUri*` URI completa).
- Middleware pode curto-circuitar **após** o roteamento (ver "Short-circuit middleware after routing").

## Ambientes
- Ambiente vem de `DOTNET_ENVIRONMENT` / `ASPNETCORE_ENVIRONMENT`; **sem definir = `Production`**. O último valor lido prevalece e não muda com o app rodando. Azure App Service adota `Production` por padrão.
- Código por ambiente: `app.Environment.IsDevelopment()` no pipeline; ao configurar serviços use `builder.Environment`.
- `launchSettings.json` só vale na máquina de desenvolvimento (e só o projeto de inicialização). Carregue configuração por ambiente (`appsettings.{ENV}.json`). Detalhes em `aspnet-configuration-options`.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Exception handler primeiro; DeveloperExceptionPage só em Development |
| 2 | `UseCors` → `UseAuthentication` → `UseAuthorization` na ordem; `UseAntiforgery` depois deles |
| 3 | `UseRouting` antes de rate limiter por endpoint e de `UseAuthorization` quando chamado explicitamente |
| 4 | Middleware após `Run` (inalcançável); `next` chamado após resposta iniciada; headers após corpo |
| 5 | Middleware customizado com dependência scoped no construtor (convenção) → mover para `InvokeAsync` ou usar `IMiddleware` |
| 6 | Trabalho longo/bloqueante dentro de middleware (afeta todas as requisições) |
| 7 | Estado por requisição guardado em campo do middleware (compartilhado entre requisições) |
| 8 | Ambiente definido corretamente em produção; segredos fora do `launchSettings.json` |

## Fontes oficiais
- Middleware: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/
- Escrever middleware: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/write
- Ativação por fábrica (`IMiddleware`): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/extensibility
- Routing: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/routing
- Ambientes: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/environments
- Boas práticas (middleware e resposta): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices
