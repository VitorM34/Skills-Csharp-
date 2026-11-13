---
name: aspnet-authentication-authorization
description: Implementar e revisar autenticação e autorização no ASP.NET Core - esquemas de autenticação, cookies, JWT Bearer, OIDC/OAuth, ASP.NET Core Identity, [Authorize], roles, claims, policies, requirements e handlers, fallback policy, resource-based (imperativa), [AllowAnonymous], 401 vs 403 em APIs. Use quando o usuário pedir login, proteger endpoints, JWT, roles/policies ou revisar segurança de acesso. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Autenticação e autorização no ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Ordem dos middlewares: `aspnet-middleware-pipeline`. CORS/CSRF/HTTPS/XSS: `aspnet-web-security`. Segredos: `aspnet-configuration-options`.

## Autenticação × autorização
**Autenticação** = quem é o usuário; **autorização** = o que ele pode fazer. **Configurar autenticação NÃO restringe endpoints automaticamente**: para exigir usuário autenticado por padrão, configure uma **fallback policy**.

## Conceitos de autenticação
- **Scheme** = nome que referencia o comportamento (authenticate/challenge/forbid) de um **handler** (`AuthenticationHandler<T>`; `RemoteAuthenticationHandler<T>` para fluxos remotos OAuth/OIDC com `CallbackPath`).
- Só um scheme registrado = é o padrão. Vários sem padrão → `InvalidOperationException: No authenticationScheme was specified...`: defina com `AddAuthentication("scheme")`/`AddAuthentication(o => ...)` ou indique `[Authorize(AuthenticationSchemes = "...")]`.
- **Challenge** é invocado pela autorização quando um usuário não autenticado acessa recurso protegido; **Forbid** quando autenticado mas sem permissão.
- Multi-tenant: não há solução nativa (a doc cita Orchard Core, ABP, Finbuckle.MultiTenant).
- **Fluxos seguros:** use a opção mais segura (Azure: **managed identities**); **evite o grant ROPG** (Resource Owner Password Credentials); segredos fora do código/arquivos (`aspnet-configuration-options`).
- **Escolha de solução:** **ASP.NET Core Identity** (APIs, UI e banco para usuários/credenciais/permissões; logins externos, MFA, senha, lockout, authenticator apps) basta na maioria dos casos. Um **servidor OIDC** é necessário quando há APIs consumidas por outros apps/SSO (tokens assinados com criptografia assimétrica). Cookies = padrão do ASP.NET Core para web apps (limitados ao domínio); tokens (JWT) não ficam presos a um domínio.

## Cookies e APIs (.NET 10)
Com cookie authentication, **endpoints de API retornam 401/403 em vez de redirecionar (302) para login**. API = controllers com `[ApiController]`, Minimal APIs que leem corpo JSON ou escrevem JSON, retornos `TypedResults`, SignalR. A detecção é por **metadata do endpoint**, não pelo header `Accept` nem pelo `Map{Verb}`; um handler que retorna `string`/`void`/`IResult` não contribui (ex.: `MapGet("/hello", () => "Hello").RequireAuthorization()` ainda redireciona). Controle: `.DisableCookieRedirect()` (ex.: no `MapGroup("/api")`) ou `AllowCookieRedirect()`/`[AllowCookieRedirect]` (este vence). XHR sempre recebe 401/403.

## JWT Bearer (doc "Configure JWT bearer authentication")
Pacote `Microsoft.AspNetCore.Authentication.JwtBearer`.
```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o => { o.Authority = "https://{authority}"; o.Audience = "https://{audience}"; });
```
- **Valide tudo na API:** assinatura (confiança/integridade), **issuer**, **audience**, **expiração**. Claims exigidas num access token OAuth 2.0: `iss, exp, aud, sub, client_id, iat, jti`. Token inválido → **401**.
- Configuração explícita: `MetadataAddress`, `TokenValidationParameters` (`ValidateIssuer/Audience/IssuerSigningKey`, `ValidAudiences/ValidIssuers`), `MapInboundClaims = false`. **Use os padrões se possível.**
- Vários emissores: APIs separadas ou `AddPolicyScheme` (seleciona o scheme pelo token).
- **Tipos de token:** access token (só para chamar APIs; **nunca** lido/interpretado pelo cliente web/UI), **ID token (nunca usar para acessar APIs)**, refresh token. Use **tokens delegados do usuário** sempre que há usuário. Sender-constrained (DPoP, mTLS) opcional.
- **Criar JWT:** **não gere seus próprios tokens** (só em teste); siga **OpenID Connect/OAuth**; **use chaves assimétricas**; **nunca crie access token a partir de usuário/senha** (vulnerável a phishing/impersonação); em web app seguro, o backend guarda os tokens e só um **cookie HTTP-only seguro** vai ao navegador; não guarde access tokens em local/session storage.

## Autorização
### Atributos e policy selection (doc "Policies")
| Metadata no endpoint | Política aplicada |
|---|---|
| nenhuma | **FallbackPolicy** (padrão `null` = sem exigência) |
| `[Authorize]`/`RequireAuthorization()` sem nome | **DefaultPolicy** (padrão: usuário autenticado) |
| `[Authorize(Policy="X")]`/`RequireAuthorization("X")` | política nomeada |
| `[Authorize(Roles="A,B")]` | política com os roles (default não é adicionada) |
| vários `[Authorize]`/`RequireAuthorization` | **combinadas; todos os requirements devem passar**; fallback não é usada |
| `[AllowAnonymous]`/`AllowAnonymous()` | sem falha de autorização (a autenticação ainda pode popular `User`) |
- **Secure by default:** `AddAuthorizationBuilder().SetFallbackPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build())` e `AllowAnonymous` nos públicos. Atenção: a fallback só vale para requisições processadas pelo middleware de autorização; **arquivos estáticos servidos antes dele não são protegidos**.
- **Roles:** `[Authorize(Roles = "Admin,SuperUser")]` = **qualquer** um dos roles; **vários atributos** = o usuário precisa estar em **todos**. Políticas por role (`policy.RequireRole(...)`).
- **Claims:** `AddPolicy("EmployeeOnly", p => p.RequireClaim("EmployeeNumber"))` (presença; ou com valores). Claim descreve **o que o sujeito é**, não o que pode fazer.
- **Requirements/handlers:** requirement (`IAuthorizationRequirement`) + handler (`AuthorizationHandler<TRequirement>` ou `IAuthorizationHandler`). Handler chama `context.Succeed(requirement)`; **não chamar Succeed não é falha** (outros handlers podem passar); `context.Fail()` **garante falha**. Todos os handlers são chamados mesmo após Succeed/Fail (efeitos como log). Registre handlers no DI (qualquer lifetime, ex.: `AddSingleton<IAuthorizationHandler, MinimumAgeHandler>()`). `IAuthorizationPolicyProvider` gera políticas dinamicamente.
- **Resource-based (imperativa):** atributos avaliam **antes** do model binding e de carregar o recurso, então `[Authorize]` **não basta** para "só o autor edita o documento". Carregue o recurso e chame `IAuthorizationService.AuthorizeAsync(user, resource, "PolicyName")`; use `authorizationResult.Succeeded`.
- Blazor: `[Authorize]` só em componentes `@page` roteados; para partes da página use `AuthorizeView`.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Endpoints sem proteção por falta de fallback policy/`[Authorize]` | Alta |
| 2 | `UseAuthentication` + `UseAuthorization` presentes e na ordem certa | Alta |
| 3 | JWT sem validação de issuer/audience/assinatura/expiração | Alta |
| 4 | API emitindo JWT a partir de usuário/senha, chave simétrica fraca, token em localStorage | Alta |
| 5 | ID token usado para chamar API | Alta |
| 6 | Autorização por recurso feita só com `[Authorize]` (IDOR) | Alta |
| 7 | Roles/claims hard-coded em strings dispersas em vez de policies nomeadas | Média |
| 8 | Handler que retorna sucesso por padrão / ausência de `Fail` onde necessário | Alta |
| 9 | API com cookies redirecionando 302 para login (retorno `string`/`IResult`) | Média |
| 10 | Arquivos estáticos sensíveis servidos antes da autorização | Alta |
| 11 | Dados de segurança em `appsettings` versionado | Alta |
| 12 | Vários schemes sem default/escolha explícita | Média |

## Fontes oficiais
- Authentication overview: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/
- Authorization introduction: https://learn.microsoft.com/en-us/aspnet/core/security/authorization/introduction
- Simple authorization: https://learn.microsoft.com/en-us/aspnet/core/security/authorization/simple
- Roles: https://learn.microsoft.com/en-us/aspnet/core/security/authorization/roles
- Claims: https://learn.microsoft.com/en-us/aspnet/core/security/authorization/claims
- Policies: https://learn.microsoft.com/en-us/aspnet/core/security/authorization/policies
- Resource-based: https://learn.microsoft.com/en-us/aspnet/core/security/authorization/resource-based
- JWT bearer: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/configure-jwt-bearer-authentication
- API endpoint auth behavior: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/api-endpoint-auth
- Identity: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/identity
- Escolher solução de identidade: https://learn.microsoft.com/en-us/aspnet/core/security/how-to-choose-identity-solution
- Secure authentication flows: https://learn.microsoft.com/en-us/aspnet/core/security/#secure-authentication-flows
