---
name: aspnet-web-security
description: Revisar e implementar segurança web no ASP.NET Core - CORS (políticas, ordem, credenciais, preflight), HTTPS e HSTS, antiforgery/CSRF (tokens, AutoValidateAntiforgeryToken, SPAs), XSS (encoding, Razor, HtmlString), redirects abertos, segredos e fluxos seguros. Use quando o usuário pedir para configurar CORS, proteger formulários, habilitar HTTPS ou revisar vulnerabilidades comuns. Based on official Microsoft Learn docs (ASP.NET Core 10; conteúdo exclusivo do .NET 11 foi desconsiderado).
---

# Segurança web no ASP.NET Core — CORS, HTTPS, CSRF, XSS

Só afirmar o que a doc oficial diz (fontes no fim). Autenticação/autorização: `aspnet-authentication-authorization`. Ordem de middleware: `aspnet-middleware-pipeline`.

## CORS
- **Same origin** = mesmo esquema + host + porta; CORS relaxa a restrição do navegador. Habilite por **middleware** (política nomeada ou padrão) **ou** por atributo `[EnableCors]`/`RequireCors` por endpoint. **Não combine** middleware e `[EnableCors]` no mesmo app (ambas as políticas se aplicam; a doc recomenda um só).
- **Ordem:** `UseCors` **depois de `UseRouting`**, **antes de `UseAuthorization`** (com endpoint routing, entre `UseRouting` e `UseEndpoints`) e **antes de `UseResponseCaching`** (para que respostas em cache tenham os headers CORS). `UseStaticFiles` normalmente vem antes de `UseCors`; apps que buscam arquivos estáticos cross-site por JavaScript precisam de `UseCors` antes de `UseStaticFiles`.
- `app.UseCors()` sozinho **não habilita CORS** sem política padrão.
- Origem permitida **sem barra final** (`https://example.com`, senão a comparação falha e não há header). Curinga de subdomínio: `SetIsOriginAllowedToAllowWildcardSubdomains` com `https://*.example.com`.
- Opções: `WithOrigins`, `WithMethods`, `WithHeaders` (casa só se os headers de `Access-Control-Request-Headers` coincidirem exatamente), `WithExposedHeaders` (por padrão o navegador não expõe todos os headers de resposta), preflight (`SetPreflightMaxAge`, `[HttpOptions]`).
- **Credenciais** (`AllowCredentials`, cookies/auth HTTP): navegador não envia por padrão (`withCredentials`); permitir é **risco de segurança** (outro site pode agir em nome do usuário logado): só para origens confiáveis. **Evite `AllowAnyOrigin` com dados sensíveis.**
- Antes do CORS existia JSONP (usa `<script>`, fora do escopo de XHR).

## HTTPS
- **Exija HTTPS** em produção: `UseHttpsRedirection` (redireciona com **307 temporário** por padrão; permanente só se configurado em não-Development) + **HSTS** (`UseHsts`) para sinalizar aos clientes que usem só HTTPS.
- **APIs:** a abordagem segura é **escutar e responder só em HTTPS**; projetos de API padrão **não incluem HSTS** (é instrução de navegador; apps móveis/desktop não obedecem; mesmo no navegador, uma chamada autenticada por HTTP em rede insegura é arriscada). Redirecionar HTTP→HTTPS pode causar `ERR_INVALID_REDIRECT` em preflight CORS.
- Porta HTTPS: variável `ASPNETCORE_HTTPS_PORT`/`HTTPS_PORT` (redirect) ≠ `ASPNETCORE_HTTPS_PORTS`/`HTTPS_PORTS` (endpoints do Kestrel). Só **uma porta HTTPS**; sem porta o middleware loga *Failed to determine the https port for redirect*. Servidor de borda (Kestrel/HTTP.sys) deve escutar HTTP e HTTPS para poder redirecionar.
- Atrás de **proxy reverso**: se o proxy trata HTTPS/redirect/HSTS, não precisa duplicar no app.

## CSRF / antiforgery (doc para .NET ≤ 10)
- Ataque: site malicioso influencia a interação do navegador com o app. **GET que muda estado é inseguro: nunca altere estado em GET.**
- **Cookies** de autenticação → sujeitos a CSRF; **tokens em header** (JWT) guardados em local storage não são enviados automaticamente (CSRF não é a preocupação principal, mas veja XSS). Hosts irmãos no mesmo domínio (`*.contoso.net`) têm confiança implícita sobre cookies.
- Implementação: ASP.NET Core Data Protection (**configure data protection em server farm**). `AddAntiforgery`/`AddRazorComponents` só **registram serviços**; **Blazor e Minimal APIs precisam chamar `UseAntiforgery` explicitamente** (depois de `UseAuthentication`/`UseAuthorization`). `AddControllers()` **não** habilita tokens: use `AddControllersWithViews()`. Formulários Razor geram token (`BeginForm`, método ≠ GET).
- **Validação:** `[ValidateAntiForgeryToken]` (inclusive GET), **`[AutoValidateAntiforgeryToken]` recomendado amplamente para cenários não-API** (só métodos inseguros), `[IgnoreAntiforgeryToken]` para exceções. APIs/SPAs: o cliente precisa enviar o token (ex.: cookie `XSRF-TOKEN` + header via `IAntiforgery`/`AntiforgeryOptions.HeaderName`).
- Várias abas com usuários diferentes (ou anônimo) não são suportadas pelo Synchronizer Token Pattern. Header `X-Frame-Options: SAMEORIGIN` é gerado por padrão (`SuppressXFrameOptionsHeader`). Em produção, proteja o cookie com `Secure`/HTTPS.
- *(A proteção CSRF automática por `Sec-Fetch-Site`/`Origin` descrita na doc é do **.NET 11** e não se aplica a projetos .NET 10.)*

## XSS
- **Nunca coloque dados não confiáveis no HTML** sem codificar. Não confiável = qualquer dado controlável por atacante: formulários, query string, headers, **dados vindos do banco**.
- Codifique conforme o contexto: HTML element → **HTML encode**; atributo → **attribute encode**; JavaScript → **JavaScript encode** (`<` vira `<`); query string de URL → **URL encode**. **Nunca** use entrada não confiável no **caminho** da URL: passe como valor de query string.
- **Razor codifica automaticamente** toda saída de variáveis com `@`. **`HtmlString`/`Html.Raw` não codificam: nunca com entrada não confiável.** Não concatene entrada em JavaScript para criar DOM nem use `document.write()` com conteúdo dinâmico.
- Em código: injete `HtmlEncoder`, `JavaScriptEncoder`, `UrlEncoder`; os encoders padrão usam a lista segura (Basic Latin) e ignoram customizações de ranges.
- **APIs** que devolvem HTML/XML/JSON podem disparar XSS nos clientes se não sanitizarem: faça **validação de entrada e codificação de saída**.

## Outros pontos da doc de segurança
- Redirecionamentos abertos: ver *Prevent open redirect attacks*. Cookies SameSite, GDPR/consentimento, IP safelist, anti-CSRF e Data Protection têm páginas próprias; consulte antes de detalhar.
- **Segredos:** nunca em arquivos de configuração em texto puro; Secret Manager em dev; fora do projeto; sem segredos de produção em dev/test; variáveis de ambiente são texto não criptografado (risco se a máquina for comprometida; a doc recomenda alternativas como Key Vault/identidades gerenciadas).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `AllowAnyOrigin` + `AllowCredentials`/dados sensíveis; origem com barra final | Alta |
| 2 | `UseCors` fora de ordem (depois de `UseAuthorization`, depois de cache) | Média |
| 3 | HTTP exposto em produção; sem HTTPS redirection/HSTS (web app); API aceitando HTTP | Alta |
| 4 | Formulário/endpoint com cookie sem antiforgery; `AddControllers` quando precisa de tokens; `UseAntiforgery` ausente em Blazor/Minimal | Alta |
| 5 | GET alterando estado | Alta |
| 6 | `Html.Raw`/`HtmlString` com entrada do usuário; entrada concatenada em JS | Alta |
| 7 | Entrada não confiável no caminho da URL | Média |
| 8 | Data Protection não configurado em server farm | Média |
| 9 | Segredos em arquivos versionados | Alta |
| 10 | API devolvendo conteúdo de usuário sem validação/encoding | Média |

## Fontes oficiais
- CORS: https://learn.microsoft.com/en-us/aspnet/core/security/cors
- Enforce HTTPS: https://learn.microsoft.com/en-us/aspnet/core/security/enforcing-ssl
- Antiforgery/CSRF: https://learn.microsoft.com/en-us/aspnet/core/security/anti-request-forgery
- XSS: https://learn.microsoft.com/en-us/aspnet/core/security/cross-site-scripting
- Open redirects: https://learn.microsoft.com/en-us/aspnet/core/security/preventing-open-redirects
- Segurança (visão geral): https://learn.microsoft.com/en-us/aspnet/core/security/
- Data Protection: https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction
- App secrets: https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets
