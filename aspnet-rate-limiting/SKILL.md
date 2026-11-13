---
name: aspnet-rate-limiting
description: Implementar e revisar rate limiting, request timeouts e compressão de resposta no ASP.NET Core - AddRateLimiter, fixed/sliding window, token bucket, concurrency, partições por usuário/IP/API key, EnableRateLimiting, UseRequestTimeouts, UseResponseCompression (Brotli/Gzip, CRIME/BREACH). Use quando o usuário pedir para proteger a API contra abuso, limitar requisições, definir timeout por endpoint ou habilitar compressão. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Rate limiting, timeouts e compressão — ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Ordem de middleware: `aspnet-middleware-pipeline`. Teste de carga: `dotnet-test-automation`.

## Rate limiting (`Microsoft.AspNetCore.RateLimiting`)
Evita abuso e sobrecarga e garante uso justo (importante em APIs públicas). **Não é solução completa contra DDoS**: a doc recomenda serviço de proteção DDoS (ex.: WAF da nuvem) em conjunto. **Os contadores ficam em memória em cada instância**: com N instâncias o limite efetivo é N × o configurado (inclusive o global); para um limite único, aplique em camada compartilhada (gateway/proxy). **Apps com rate limiting devem ser testados sob carga e revisados antes do deploy.**
```csharp
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("fixed", o => { o.PermitLimit = 4; o.Window = TimeSpan.FromSeconds(12); o.QueueLimit = 2; });
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            ctx.User.Identity?.Name ?? ctx.Request.Headers.Host.ToString(),
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});
app.UseRouting();
app.UseRateLimiter();            // depois de UseRouting se usar [EnableRateLimiting]/por endpoint
app.MapGet("/", () => "ok").RequireRateLimiting("fixed");
```
- **Global limiter** (`options.GlobalLimiter`) aplica a todos os endpoints; **policies nomeadas** precisam ser aplicadas explicitamente (`RequireRateLimiting("x")`, `[EnableRateLimiting("x")]`, `[DisableRateLimiting]`). Configure os limites via **Configuration** (classe de options), não hard-coded.
- **Algoritmos:** *Fixed window* (janela fixa; reinicia ao expirar), *Sliding window* (segmentos que devolvem permissões), *Token bucket* (repõe um número fixo de tokens por período; nunca excede o limite do bucket; `AutoReplenishment` ou `TryReplenish` manual), *Concurrency* (limita **apenas** requisições simultâneas, não por período). Escolha considerando o **custo do endpoint** (tempo, dados, CPU, I/O).
- **Partições:** limite por IP, por **identidade do usuário**, por **API key** ou por caminho; beneficia **justiça** (um usuário não consome o limite de todos). `PartitionedRateLimiter.CreateChained` combina limitadores (global em cadeia; por endpoint via política nomeada).
- Blazor server-side: `[EnableRateLimiting]` só em componente roteável (ou `RequireRateLimiting` em `MapRazorComponents`).
- Atrás de proxy, o IP pode não ser o do cliente (ver forwarded headers); antes de particionar por IP confirme como o app obtém o IP.

## Request timeouts (`UseRequestTimeouts`)
- Servidores ASP.NET Core **não aplicam timeout de requisição por padrão** (processamentos variam: WebSockets, estáticos, APIs caras). O middleware configura **por endpoint** e um **timeout global**.
- Ao estourar: `HttpContext.RequestAborted` é cancelado (`IsCancellationRequested`); **`HttpContext.Abort` não é chamado**, então o app ainda pode escrever resposta; se não tratar, retorna **504**.
- Políticas nomeadas, status code configurável, delegate por política, `[DisableRequestTimeout]`/`DisableRequestTimeout()`, e `IHttpRequestTimeoutFeature.DisableTimeout()` para cancelar um timeout **antes** de expirar (não depois). `UseRequestTimeouts` **depois de `UseRouting`** quando este é chamado explicitamente.
- **Respeite o `CancellationToken`** da requisição nos handlers (ver `csharp-async-await`).

## Compressão de resposta (`UseResponseCompression`)
- **Prefira compressão do servidor** (IIS, Apache, Nginx): o middleware provavelmente **não alcança** o desempenho dos módulos do servidor; Kestrel e HTTP.sys não têm compressão embutida.
- Comprime tipos não comprimidos nativamente (CSS, JS, HTML, XML, JSON); **não comprima PNG etc.** O cliente envia `Accept-Encoding`; o servidor responde com `Content-Encoding` e `Vary: Accept-Encoding`. Provedores padrão: **Brotli** (padrão) e **Gzip**; MIME types padrão extensíveis; `Content-Type` deve estar definido.
- **Compressão sobre HTTPS** é **desabilitada por padrão** (`EnableForHttps`) por risco de ataques **CRIME e BREACH** em páginas dinâmicas; só habilite entendendo mitigação (ex.: antiforgery, não refletir segredos).
- `UseResponseCompression` **antes** de qualquer middleware que comprima respostas. A ordem entre cache e compressão depende do app (ver `aspnet-caching`).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | API pública sem rate limiting (login, buscas caras, criação) |
| 2 | `UseRateLimiter` antes de `UseRouting` com políticas por endpoint |
| 3 | Política nomeada definida mas não aplicada a endpoints |
| 4 | Partição inadequada (todos no mesmo bucket; ou IP errado atrás de proxy) |
| 5 | Limites hard-coded e não testados sob carga |
| 6 | Operações longas sem timeout nem respeito ao `RequestAborted` |
| 7 | Compressão habilitada sobre HTTPS sem avaliar CRIME/BREACH; compressão de arquivos já comprimidos |
| 8 | Compressão no app quando o servidor/proxy já comprime |

## Fontes oficiais
- Rate limiting: https://learn.microsoft.com/en-us/aspnet/core/performance/rate-limit
- Request timeouts: https://learn.microsoft.com/en-us/aspnet/core/performance/timeouts
- Response compression: https://learn.microsoft.com/en-us/aspnet/core/performance/response-compression
- Middleware order: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/#middleware-order
