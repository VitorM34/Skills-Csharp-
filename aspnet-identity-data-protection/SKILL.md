---
name: aspnet-identity-data-protection
description: Implementar e revisar ASP.NET Core Identity (usuários, senhas, lockout, confirmação de e-mail, 2FA/MFA TOTP, passkeys, cookies, Identity API endpoints para SPAs, security stamp) e ASP.NET Core Data Protection (IDataProtector, purpose strings, key ring, persistência de chaves, SetApplicationName, web farm, containers, rotação de 90 dias, proteção das chaves em repouso). Use quando o usuário pedir login/cadastro, políticas de senha, MFA, "usuários deslogando após deploy/escala", cookie de autenticação ou criptografar dados em apps. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Identity e Data Protection

Só afirmar o que a doc oficial diz (fontes no fim). Autenticação/autorização geral, JWT e policies: `aspnet-authentication-authorization`. CSRF/XSS/HTTPS: `aspnet-web-security`. Configuração/segredos: `aspnet-configuration-options`. Modelagem EF do Identity: `efcore-migrations-modeling`.

## O que é Identity (e o que não é)
- API + UI de login que gerencia **usuários, senhas, perfil, roles, claims, tokens, confirmação de e-mail** etc.; armazena em banco (SQL Server/SQLite, outro store via provider). Suporta **provedores externos** (Google, Microsoft, Facebook, Twitter). **Não tem relação com a Microsoft identity platform (Entra/Azure AD)**, que é uma alternativa.
- Templates: `dotnet new blazor|webapp|mvc -au Individual`. Em Razor Pages/MVC a UI vem como **Razor class library** (área `Identity`; dá para *scaffold* páginas individuais); em Blazor Web App vêm **componentes** em `Components/Account` (**mudam a cada release**).
- Registro típico: `AddDefaultIdentity<IdentityUser>(o => o.SignIn.RequireConfirmedAccount = true).AddEntityFrameworkStores<ApplicationDbContext>()` com `ApplicationDbContext : IdentityDbContext`. `AddDefaultIdentity` inclui UI e TOTP; `AddIdentity` dá controle manual (e permite desligar TOTP). Padrão do Program.cs: `Add{Service}` **antes** de `Configure{Service}`; `IdentityOptions` e `ConfigureApplicationCookie` devem vir **depois** de `AddIdentity/AddDefaultIdentity`.

## Opções (defaults oficiais) — revise, não aceite cegamente
| Área | Defaults |
|---|---|
| **Senha** | exige maiúscula, minúscula, dígito e não alfanumérico; **tamanho mínimo 6**; `RequiredUniqueChars = 1`. Ajuste por `PasswordOptions` **e** pelos `[StringLength]` das páginas scaffolded (`Register`, `ResetPassword`). |
| **Lockout** | `AllowedForNewUsers = true`, **5 tentativas**, bloqueio de **5 min**; só vale se o login chama `PasswordSignInAsync(..., lockoutOnFailure: true)`; login com sucesso zera o contador. |
| **SignIn** | `RequireConfirmedEmail = false`, `RequireConfirmedPhoneNumber = false` (a template usa `RequireConfirmedAccount = true`). |
| **User** | `RequireUniqueEmail = false`; `AllowedUserNameCharacters` limitado. |
| **PasswordHasher** | `CompatibilityMode = IdentityV3` (PBKDF2), `IterationCount = 100000`. **Para senhas use `PasswordHasher`; não use `KeyDerivation.Pbkdf2` para guardar senha** (aviso oficial). |
| **Cookie** | `ConfigureApplicationCookie`; `IsEssential = true` por padrão; `SameSite` Lax por padrão. |
- **Security stamp / "sign out everywhere":** `ISecurityStampValidator` regenera o `ClaimsPrincipal` quando algo sensível muda (senha, roles); com cookies é **revalidado periodicamente** (`SecurityStampValidatorOptions.ValidationInterval`); com tokens, o tempo de vida do access token (`BearerTokenOptions.BearerTokenExpiration`) limita quanto a sessão sobrevive à mudança.
- **Exigir autenticação global:** fallback policy (ver `aspnet-authentication-authorization`).

## Confirmação de e-mail e recuperação de senha
Fluxo oficial: registrar → enviar link de confirmação via **`IEmailSender`** (a template só *simula* o e-mail até você implementar e registrar o serviço) → `RequireConfirmedAccount`. Reset de senha usa tokens do `TokenOptions` (provedores de token configuráveis). Implemente envio real, tokens com expiração (⚠ **fora da doc lida:** evitar revelar se um e-mail existe é prática geral de segurança, não verificada nas páginas oficiais desta skill).

## MFA, 2FA, passkeys
- **2FA é suportado por padrão** (`TwoFactorEnabled` por usuário; UI padrão tem as páginas); **TOTP** com apps autenticadores (Microsoft/Google Authenticator; QR codes exigem implementação própria — ver doc *identity-enable-qrcodes*). **MFA** = 2 ou mais fatores; 2FA = exatamente 2.
- **Passkeys (WebAuthn/FIDO2)** são suportadas na documentação do ASP.NET Core 10: resistentes a phishing, sem segredo compartilhado (servidor guarda só a chave pública). Há guia específico para Blazor. Para MFA com OpenID Connect externo, ver doc *mfa*.

## Identity API endpoints para SPAs/clientes
- `AddIdentityApiEndpoints<IdentityUser>()` + `AddEntityFrameworkStores` + **`MapIdentityApi<IdentityUser>()`** (requer net8+). **Cookies são recomendados para apps de navegador** (o browser trata sem expor ao JavaScript; no `fetch` use `credentials: 'include'`); cookie é emitido no `/login` com `useCookies` ou `useSessionCookies=true`.
- **Tokens do Identity API não são JWT**: são **tokens proprietários** (access token curto + **refresh token** via `POST /refresh`), "uma alternativa para clientes que não podem usar cookies"; **não é um servidor de tokens completo** — para isso use outro provedor (ver `aspnet-authentication-authorization`). Você é responsável por guardar tokens com segurança.
- Proteja endpoints com `RequireAuthorization()` (ou `[Authorize]` em controllers), incluindo Swagger se necessário.

## Cookies de autenticação (resumo útil)
Cookie é protegido pelo **Data Protection**; atrás de várias máquinas, todas precisam **do mesmo key ring e mesmo app identifier**. Persistência entre sessões só com consentimento ("lembrar de mim"). `MinimumSameSitePolicy` do cookie policy pode **sobrescrever** `Cookie.SameSite` (Strict quebra OAuth/cross-origin). `CookieAuthenticationEvents.ValidatePrincipal` permite revalidar a cada requisição e mitigar acesso de usuários revogados.

## Data Protection
- API criptográfica de alto nível com **gestão e rotação de chaves** (substitui `<machineKey>`); **o DPAPI do Windows não é para web apps**. Protege cookies de auth, antiforgery, tokens de Identity etc. Design: "configuração fácil", API difícil de usar errado, o dev não gerencia algoritmos.
- **Uso:** injete `IDataProtectionProvider` e chame **`CreateProtector(purpose)`** com **purpose string única** (isola consumidores; regra prática: namespace+tipo, com versão, ex.: `Contoso.Security.BearerToken.v1`; array `["...","v1"]` permite hierarquia/multi-tenant). A purpose não precisa ser secreta. **`ITimeLimitedDataProtector`** (pacote `Microsoft.AspNetCore.DataProtection.Extensions`) cria payloads que expiram (ex.: token de 1 h). Para senhas: `PasswordHasher`, nunca Data Protection.
- **Defaults:** chaves com **90 dias** de vida (rotação automática; chaves aposentadas continuam a descriptografar). **Não delete chaves** (dado protegido ficaria inacessível). Algoritmo padrão **AES-256-CBC + HMACSHA256**. Onde guarda por padrão: Azure App Service → `%HOME%\ASP.NET\DataProtection-Keys` (compartilhado entre instâncias do **mesmo slot**; **slots Staging/Production NÃO compartilham** ⇒ swap desloga usuários); perfil de usuário → `%LOCALAPPDATA%\ASP.NET\DataProtection-Keys` (criptografado com DPAPI no Windows); IIS → registro HKLM (DPAPI); **caso contrário as chaves ficam só em memória e se perdem ao reiniciar**.
- **Web farm / containers:** configure explicitamente: persistir chaves num **volume Docker** persistente ou provedor externo (**Azure Blob + Key Vault, Redis, sistema de arquivos/UNC**, etc.) com `PersistKeysTo...`, **`SetApplicationName("mesmo-valor")`** (por padrão o isolamento usa o **content root**, então apps/instâncias com caminhos diferentes não leem os dados um do outro; para compartilhar payloads entre apps use o mesmo nome **e a mesma versão do stack**). Overrides desativam a criptografia automática de chaves em repouso: **reative com `ProtectKeysWith...`** (Key Vault, certificado). O key ring deve ter **permissões restritas ao app** (equivale a segredo de configuração; criptografar não impede um atacante com escrita de criar chaves novas).
- Perda/troca do key ring ⇒ usuários deslogados, antiforgery/tokens inválidos, dados protegidos ilegíveis.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Várias instâncias/containers sem key ring compartilhado persistente + mesmo `SetApplicationName` | Alta |
| 2 | Keys só em memória/diretório efêmero de container; chaves apagadas | Alta |
| 3 | Key ring em local legível por outros processos/sem criptografia em repouso quando evitável | Alta |
| 4 | Senha com `KeyDerivation.Pbkdf2` caseiro ou hash próprio em vez de `PasswordHasher` | Alta |
| 5 | Política de senha/lockout padrão sem revisão (mín. 6 caracteres); `lockoutOnFailure:false` no login | Média |
| 6 | `RequireConfirmedAccount` sem `IEmailSender` real (ninguém consegue confirmar, ou confirmação ignorada) | Média |
| 7 | Cookie auth sem HTTPS/`Secure`/`HttpOnly` ou `SameSite` incorretos; "lembrar de mim" sem consentimento | Média |
| 8 | Identity API com tokens proprietários tratados como JWT/servidor de tokens completo | Média |
| 9 | Purpose string genérica/reutilizada entre componentes | Média |
| 10 | Roles/claims alterados sem efeito imediato (stamp/validação) em sessões longas | Média |
| 11 | 2FA/MFA ausente em áreas administrativas; sem plano para recuperação de conta | Média |
| 12 | Deploy com slots (swap) deslogando usuários por key ring separado | Média |

## Fontes oficiais
- Introduction to Identity: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/identity
- Configure Identity: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/identity-configuration
- Identity API para SPAs: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/identity-api-authorization
- MFA: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/mfa
- Passkeys: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/passkeys/
- Confirmação de conta e recuperação de senha: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/accconfirm
- Cookie authentication: https://learn.microsoft.com/en-us/aspnet/core/security/authentication/cookie
- Data Protection overview: https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction
- Configurar Data Protection: https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/configuration/overview
- Defaults de chaves/lifetime: https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/configuration/default-settings
- Purpose strings: https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/consumer-apis/purpose-strings
- Payloads com tempo limitado: https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/consumer-apis/limited-lifetime-payloads
- Hash de senhas (aviso sobre Pbkdf2): https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/consumer-apis/password-hashing
