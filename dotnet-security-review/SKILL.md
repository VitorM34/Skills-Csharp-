---
name: dotnet-security-review
description: Revisão de segurança de aplicações .NET / ASP.NET Core organizada pelo OWASP Top 10:2025 (controle de acesso, misconfiguration, supply chain, criptografia, injection, design inseguro, autenticação, integridade/desserialização, logging, tratamento de exceções), mapeando cada risco para a documentação oficial da Microsoft e para as regras de analyzers de segurança do SDK (CA2100, CA3001–CA3012, CA23xx, CA53xx), mais upload de arquivos, segredos, NuGet Audit e HTTPS/HSTS. Use quando o usuário pedir "revisão de segurança", "isso é seguro?", "OWASP", pen-test preparatório, ou antes de ir para produção. Marca explicitamente o que NÃO está coberto por doc oficial (ex.: SSRF genérico).
---

# Revisão de segurança .NET (OWASP Top 10:2025 → documentação oficial)

**Proveniência:** a *lista de riscos* vem do **OWASP Top 10:2025** (fonte **externa**, https://top10.owasp.org/2025/). Cada *como mitigar em .NET* vem da **documentação oficial da Microsoft** (links no fim). Onde a doc oficial não cobre o risco, está escrito **"sem doc oficial lida"** — nessas partes não invente; use a lista de verificação só como pergunta, não como regra.
Skills que aprofundam: `aspnet-web-security`, `aspnet-authentication-authorization`, `aspnet-identity-data-protection`, `aspnet-configuration-options`, `aspnet-error-handling`, `aspnet-logging`, `aspnet-validation`, `aspnet-rate-limiting`, `aspnet-hosting-deployment`, `dotnet-json-serialization`, `efcore-sql-performance`, `dotnet-exception-handling`, `dotnet-project-tooling`.

## Como conduzir a revisão
1. **Automatize o que o SDK já checa.** Os analyzers de **segurança** (categoria *Security*: CA2100, CA23xx desserialização, CA3001–CA3012 taint/injection, CA3075 XML, CA53xx cripto/cookies/tokens) **não vêm habilitados por padrão** (a doc marca "Enabled by default in .NET 10: No" em cada uma). Para ligar: `<AnalysisModeSecurity>All</AnalysisModeSecurity>` (MSBuild, só para a categoria) ou `dotnet_analyzer_diagnostic.category-Security.severity = warning|error` (`.editorconfig`). Ver `dotnet-project-tooling`.
   - Limites das regras de *taint* (CA3001–CA3012): **não rastreiam dados entre assemblies** e têm limite configurável de profundidade; a ausência de warning **não prova** que está seguro.
   - A doc manda: se desabilitar uma regra de segurança, **marque o motivo no código e informe o responsável por segurança** do projeto. Suprima só quando a entrada é sempre validada contra um conjunto seguro conhecido.
2. Rode a **revisão por categoria** abaixo, lendo `Program.cs`, `appsettings*.json`, `*.csproj`, controllers/endpoints, acesso a dados e Dockerfile.
3. Reporte com severidade, arquivo:linha, regra/skill de origem e fonte.

## A01 — Broken Access Control
- **Secure by default:** em app server-side onde quase tudo exige login, defina a **fallback policy** exigindo usuário autenticado (`SetFallbackPolicy`) — protege endpoints novos que **não têm metadata de autorização**; a *default policy* só vale quando o endpoint usa `[Authorize]`/`RequireAuthorization()` sem nome de policy. Liberações explícitas com `[AllowAnonymous]` devem ser revisadas uma a uma. Ver `aspnet-authentication-authorization`.
- **CORS não é recurso de segurança:** "CORS relaxa a segurança; uma API não fica mais segura por permitir CORS". Revise origens permitidas (`aspnet-web-security`).
- **CSRF** (cookies): ver A08. **Open redirect:** use `LocalRedirect`/`Results.LocalRedirect` (lança exceção se a URL não for local) em vez de `Redirect(urlDoUsuario)`; redirecione só localmente ou para URL conhecida; trate todo dado do usuário como não confiável.
- **Upload de arquivos:** grave em área dedicada (de preferência fora do drive do sistema), **sem permissão de execução**; nome de arquivo **gerado pelo app** (`Path.GetRandomFileName`), nunca o `IFormFile.FileName` (só para exibir/logar, com HTML encode e `Path.GetFileName`); permita só extensões aprovadas; limite de tamanho; não sobrescrever arquivos de mesmo nome; **rode antivírus/malware scan antes de armazenar**.
- Verificação de propriedade do recurso (IDOR/autorização por recurso): sem página oficial lida com esse rótulo; use autorização baseada em recurso (`aspnet-authentication-authorization`) e confira que **toda** consulta filtra pelo usuário/tenant.

## A02 — Security Misconfiguration
- **HTTPS/HSTS (oficial):** `UseHttpsRedirection` (redirect **307** por padrão; a doc recomenda redirects temporários) + `UseHsts` **fora de Development** (HSTS é altamente cacheável; por padrão exclui `localhost`/`127.0.0.1`/`[::1]`). `max-age` padrão **30 dias**; **ao introduzir HTTPS pela 1ª vez use valor pequeno (horas, no máximo 1 dia)** e só aumente com confiança; `preload` e `includeSubDomains` são opcionais e exigem cuidado. HSTS depende de uma 1ª requisição HTTPS bem-sucedida: "nenhuma API impede o cliente de enviar dados sensíveis na primeira requisição".
- **APIs:** o mais seguro é **escutar e responder só em HTTPS** (ou rejeitar HTTP); **não** use `[RequireHttps]` em Web APIs que recebem dados sensíveis (clientes podem não seguir o redirect e enviar por HTTP); templates de API não incluem HSTS porque é instrução só de navegador.
- **Atrás de reverse proxy:** `UseForwardedHeaders`, `KnownProxies/KnownNetworks`, `AllowedHosts` obrigatório (`aspnet-hosting-deployment`). Em 10, `KnownNetworks` é obsoleto (→ `KnownIPNetworks`).
- **Segredos/config:** nunca em código ou arquivos de config em texto puro; **não use segredos de produção em dev/test**; segredos fora do projeto (para não irem ao repositório); **User Secrets só em desenvolvimento** (valores **não criptografados**; não dependa do formato/local); **variáveis de ambiente são texto puro** e a doc **desaconselha guardar connection string de produção nelas**; em produção use **Azure Key Vault** (ou equivalente) com **Managed Identity**; evite o *Resource Owner Password Credentials grant* (expõe a senha ao cliente).
- **Certificados/TLS:** não desabilite validação de certificado (CA5359: callback sempre `true`), não use protocolos obsoletos (CA5364/CA5397/CA5398), não deixe checar CRL desligada no `HttpClient` (CA5399/CA5400), nem adicione certificados ao root store (CA5380/CA5381).
- Developer Exception Page, mensagens detalhadas, Swagger/OpenAPI e `EnableDetailedErrors` do gRPC só em Development (ver `aspnet-error-handling`, `aspnet-grpc`, `aspnet-openapi`). Kestrel: limites de corpo/headers/data rate (`aspnet-hosting-deployment`).
- **Código "legado" desaconselhado pela doc (*Secure coding guidelines*):** não usar Code Access Security, código em confiança parcial, `AllowPartiallyTrustedCaller`, .NET Remoting, DCOM nem **binary formatters**; para código de origem desconhecida use isolamento de SO (virtualização, AppContainers, usuários/permissões, containers Hyper-V).

## A03 — Software Supply Chain Failures
- **NuGet Audit** (oficial): avisa de pacotes com vulnerabilidade conhecida **no restore**. Histórico: .NET 8 = só dependências diretas; .NET 9 = também transitivas; **projetos `net10.0`+ usam `NuGetAuditMode=all`** (senão `direct`). Propriedades: `NuGetAudit` (padrão `true`), `NuGetAuditMode` (`direct|all`), `NuGetAuditLevel` (padrão `low`; `moderate|high|critical`). Avisos **NU1901–NU1904** (low→critical); **NU1905** se a fonte de auditoria não fornece dados; **NU1900** erro ao consultar. Fontes de auditoria: `auditSources` no `NuGet.Config` (nuget.org, ou `data.nuget.org`, que só serve dados de vulnerabilidade). Trate NU190x como **falha de build** em CI (ver `dotnet-project-tooling`, `TreatWarningsAsErrors`/`WarningsAsErrors`). Quando há aviso, a vulnerabilidade já é pública ⇒ **aja rápido**.
- Comandos: `dotnet list package --vulnerable`, `dotnet list package --deprecated`, `dotnet nuget why <pacote>` (por que um transitivo está no grafo); NuGet 7 / SDK 10: `dotnet package update --vulnerable`.
- **Boas práticas oficiais:** conheça suas dependências (diretas e transitivas); mantenha SDK/runtime/NuGet/pacotes atualizados; **`nuget.config` na raiz com `<clear />`** (repetibilidade); **use fontes confiáveis e saiba de qual feed vem cada pacote** (Dependency Confusion): feed único/privado com upstream; **Package Source Mapping** (aplica-se só ao baixar na restore/install/update — não impede o envio de IDs de pacotes a todas as fontes em comandos de consulta); **lock files** (hash do conteúdo para repetibilidade); **client trust policies** (exigir pacotes assinados); permissões do `nuget.config` (não legível por outros usuários); cuidado com solução na pasta Downloads (MSBuild importa `Directory.Build.props` de pastas pai); build agents sem reset acumulam risco; credenciais de feed privado via mecanismo seguro. Dependabot/GitHub Security são citados pela doc.

## A04 — Cryptographic Failures
- **Algoritmos (analyzers):** CA5350 (TripleDES, SHA1, RIPEMD160 = fracos), CA5351 (**MD5, DES, RC2** quebrados), CA5358 (modos de cifra inseguros; a doc explica que **ECB não é seguro**), CA5384 (DSA), CA5385 (RSA com chave insuficiente), CA5373/CA5387/CA5388/CA5379 (derivação de chave fraca/iterações insuficientes).
- **Segredos hardcoded:** CA5390 (chave de criptografia fixa em `AesGcm`/`AesCcm`/`SymmetricAlgorithm.Key`), CA5403 (certificado hardcoded). Guarde chaves em Key Vault/cofre.
- **Aleatoriedade:** **CA5394** — `System.Random` é fraco para valores de segurança; use **`RandomNumberGenerator`**.
- **Senhas:** `PasswordHasher` do Identity; **não** use `KeyDerivation.Pbkdf2` para armazenar senhas (aviso oficial). **Dados da aplicação:** Data Protection (`aspnet-identity-data-protection`) em vez de criptografia caseira.
- Cripto em geral: a doc conceitual (*cryptographic services*) descreve chaves secretas (proteger a chave de acesso não autorizado), IV, HMAC etc.; prefira APIs de alto nível do framework.

## A05 — Injection
- **SQL (EF Core, oficial):** `FromSql` (interpolado) e `FromSqlInterpolated` **são seguros** — o valor vira `DbParameter`. **`FromSqlRaw` pode ser vulnerável** se concatenar entrada do usuário. Nomes de coluna/tabela **não podem ser parametrizados**: se for realmente dinâmico, a doc diz primeiro para **reconsiderar** (permitir o usuário escolher coluna pode expor coluna não indexada/sensível) e preferir duas consultas para duas colunas; se inevitável, use `FromSqlRaw` **com validação rigorosa do identificador** (ver `efcore-sql-performance`). ADO.NET: **CA2100** (CommandText montado de argumento) e **CA3001**. Use comandos parametrizados ou stored procedures.
- **XSS (oficial):** Razor **codifica automaticamente** `@variavel`; perigos: **`Html.Raw`/`HtmlString` com dado não confiável**, `document.write`, concatenar dado não confiável em JS/DOM. Regras: HTML-encode em elementos, **atributo-encode** em atributos, **JS-encode** (ou, melhor, coloque o dado num `data-*` e leia no JS com `textContent`/`createTextNode`), **URL-encode** em query string, **nunca use dado não confiável como parte do *caminho* da URL** (passe como valor de query). Dado "não confiável" inclui **query string, headers e o que vem do banco** (o banco pode ter sido comprometido). **Web APIs** que devolvem HTML/XML/JSON também podem causar XSS no cliente: valide entrada **e** faça output encoding. Os encoders usam por padrão a lista segura **Basic Latin**; personalizações só valem para encoders injetados por DI. Analyzer: CA3002.
- **Outras injeções (analyzers de taint, "Review code for…"):** caminho de arquivo CA3003, divulgação de informação CA3004, **LDAP CA3005**, **comando de processo CA3006**, open redirect CA3007, **XPath CA3008**, XML CA3009, DLL CA3011, **regex CA3012**.
- **XML/XXE:** CA3075 (DTD inseguro), CA3076 (script XSLT), CA3077, CA3061 (schema por URL), CA5369–CA5372 (use `XmlReader` com configuração segura). A doc descreve que XML não confiável processado sem `XmlReader` seguro pode levar a **DoS, divulgação de informação e SSRF** (nesse contexto de XML).
- **SSRF genérico** (a app chamar URLs fornecidas pelo usuário com `HttpClient`): **sem doc oficial lida**; trate como pergunta de revisão (a URL de destino vem do usuário? há validação/allowlist?) e peça decisão de design, sem citar "regra oficial".
- **Zip Slip:** CA5389 — não use o caminho de entrada do arquivo compactado como caminho de destino sem sanitizar.

## A06 — Insecure Design
Sem doc oficial .NET lida que trate "design inseguro" como categoria. A doc de upload referencia **threat modeling** (Azure). Use esta categoria como pergunta de revisão: limites de abuso (`aspnet-rate-limiting`), validação (`aspnet-validation`), segregação de privilégios, fluxos de recuperação de conta (`aspnet-identity-data-protection`).

## A07 — Authentication Failures
- **Identity:** defaults a revisar — senha mínima **6**, lockout **5 tentativas/5 min** (só se o login usa `lockoutOnFailure`), `RequireConfirmedAccount`, **2FA/TOTP e passkeys** disponíveis (ver `aspnet-identity-data-protection`). Evite *ROPG*; prefira fluxos seguros e **Managed Identities** para serviços Azure.
- **Cookies:** `Secure`, `HttpOnly`, `SameSite` adequados; **CA5382/CA5383** (cookie sem `Secure` ao usar `IResponseCookies.Append`); persistência ("lembrar de mim") só com consentimento; cookies de autenticação são protegidos pelo Data Protection (key ring compartilhado em web farm).
- **JWT/tokens:** **CA5404** — não desligue `ValidateIssuer`, `ValidateAudience`, `ValidateLifetime`, `RequireExpirationTime`; CA5405 (não pular validação sempre em delegates).
- Revalidar cookie a cada requisição (`ValidatePrincipal`) mitiga usuário revogado; mudanças de segurança → regenerar principal (security stamp).

## A08 — Software or Data Integrity Failures
- **Desserialização (oficial):** **`BinaryFormatter.Deserialize` nunca é seguro com entrada não confiável**; "é inseguro e **não pode ser tornado seguro**"; **a partir do .NET 9 a implementação in-box lança exceção** (as chaves antigas de habilitação foram removidas). Também perigosos (polimorfismo irrestrito): `SoapFormatter`, `LosFormatter`, `NetDataContractSerializer`, `ObjectStateFormatter`. **Alternativas seguras**: `System.Text.Json`, `XmlSerializer`, `DataContractSerializer` (não confundir com `NetDataContractSerializer`), `BinaryReader/BinaryWriter` para formatos próprios. **Não presuma que o dado é confiável**: payloads cruzam fronteiras de confiança sem o dev perceber (ex.: cliente desktop interno comprometido). Analyzers: CA2300–CA2362 (BinaryFormatter, NetDataContractSerializer, LosFormatter, JavaScriptSerializer com `SimpleTypeResolver`, `TypeNameHandling` ≠ None do Newtonsoft [CA2326–CA2330], `DataSet/DataTable` inseguros [CA2350–CA2362]), CA5360 (métodos perigosos em desserialização). Ver `dotnet-json-serialization`.
- **CSRF (oficial):** só importa para auth por **cookie** (e Basic/Digest); token em *local storage* não sofre CSRF. **GET nunca deve alterar estado.** Antiforgery: `AddAntiforgery` **só registra serviços — Minimal APIs/Blazor precisam de `UseAntiforgery()` explícito**; MVC: `[AutoValidateAntiforgeryToken]`/`[ValidateAntiForgeryToken]`; `BeginForm` gera token (não-GET); `IgnoreAntiforgeryToken` com cuidado. Cookie antiforgery com `SecurePolicy = Always` fora de Development. Apps no **mesmo domínio pai** compartilham confiança implícita de cookies ⇒ prefira domínios separados. Analyzers: **CA5391** (ações que modificam sem token), CA3147, CA5395. Cuidado: parte do CSRF "automático" é só .NET 11 (não considerar no 10).
- **Integridade da cadeia:** pacotes assinados/lock files (A03).

## A09 — Security Logging and Alerting Failures
- **Não logue dados sensíveis** (senhas, tokens, PII); nome de arquivo enviado deve ser HTML-encoded ao logar (doc de upload); mensagens de exceção detalhadas ao cliente são divulgação de informação (CA3004). Logs estruturados e níveis: `aspnet-logging`.
- **Alertas/telemetria:** métricas built-in do ASP.NET Core 10 incluem **`aspnetcore.authentication.challenges`** e **`aspnetcore.authorization.attempts`** (autenticação/autorização; ver a página de métricas de segurança) e `aspnetcore.diagnostics.exceptions`; use para alertar picos de falha de login/autorização (`dotnet-observability`). Procedimento de incidente: `dotnet-production-diagnostics`.

## A10 — Mishandling of Exceptional Conditions
- Trate erros de forma global (`UseExceptionHandler`/`IExceptionHandler` + `ProblemDetails`) **sem vazar stack trace/detalhes** fora de Development (`aspnet-error-handling`, `dotnet-exception-handling`). **CA2153:** não capture *Corrupted State Exceptions* — permitir o crash é mais seguro que continuar com memória corrompida.
- Falhar fechado: erro de autorização/validação deve negar, não permitir (ver fallback policy).

## Checklist de revisão (resumo, ordene por severidade)
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `FromSqlRaw`/ADO.NET com concatenação de entrada do usuário; nome de coluna dinâmico sem validação | Alta |
| 2 | `BinaryFormatter`/`NetDataContractSerializer`/`LosFormatter`/`SoapFormatter` ou `TypeNameHandling` ≠ None com dado externo | Alta |
| 3 | Endpoint novo sem autenticação (sem fallback policy; `[AllowAnonymous]` indevido); autorização sem checar dono do recurso | Alta |
| 4 | Segredos em código/`appsettings`/imagem Docker; connection string de produção em variável de ambiente; chave/certificado hardcoded (CA5390/CA5403) | Alta |
| 5 | Validação de certificado/token desligada (CA5359, CA5404); protocolos obsoletos | Alta |
| 6 | `Html.Raw`/`HtmlString` com dado não confiável; dado não confiável em JS/URL path | Alta |
| 7 | Redirect com URL do usuário sem `LocalRedirect`; cookies de auth sem `Secure`/HttpOnly; CSRF sem antiforgery em app com cookie | Alta |
| 8 | Upload: nome do usuário usado no disco, sem limite/extensão/scan, pasta executável; Zip Slip | Alta |
| 9 | Sem HTTPS/HSTS corretos; HSTS agressivo na 1ª implantação; API com `[RequireHttps]`; CORS aberto | Média/Alta |
| 10 | Pacotes com NU1901–NU1904 ignorados; sem `nuget.config` controlado/lock files/source mapping; NuGetAudit desligado | Média |
| 11 | MD5/SHA1/DES/3DES/ECB; `Random` para token/senha (CA5394); Pbkdf2 caseiro para senha | Média/Alta |
| 12 | Detalhes de exceção, Developer Exception Page, gRPC `EnableDetailedErrors` ou Swagger expostos em produção | Média |
| 13 | Analyzers de segurança desligados (nenhuma regra Security ativa) e supressões sem justificativa | Média |
| 14 | Dados sensíveis em logs; sem alerta para falhas de auth | Média |
| 15 | SSRF (URL do usuário em `HttpClient`) — **sem doc oficial lida**: levante como pergunta | Verificar |

## Fontes
**Externa (lista de riscos):** OWASP Top 10:2025 — https://top10.owasp.org/2025/
**Oficiais (Microsoft Learn):**
- ASP.NET Core security (visão geral, autenticação segura, segredos): https://learn.microsoft.com/en-us/aspnet/core/security/
- XSS: https://learn.microsoft.com/en-us/aspnet/core/security/cross-site-scripting
- CSRF/antiforgery: https://learn.microsoft.com/en-us/aspnet/core/security/anti-request-forgery
- Open redirect: https://learn.microsoft.com/en-us/aspnet/core/security/preventing-open-redirects
- HTTPS/HSTS: https://learn.microsoft.com/en-us/aspnet/core/security/enforcing-ssl
- CORS: https://learn.microsoft.com/en-us/aspnet/core/security/cors
- Segredos em desenvolvimento: https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets
- Key Vault (configuração): https://learn.microsoft.com/en-us/aspnet/core/security/key-vault-configuration
- Políticas de autorização / fallback: https://learn.microsoft.com/en-us/aspnet/core/security/authorization/policies
- Upload de arquivos: https://learn.microsoft.com/en-us/aspnet/core/mvc/models/file-uploads
- SQL injection (EF Core, `FromSql`): https://learn.microsoft.com/en-us/ef/core/querying/sql-queries
- BinaryFormatter (riscos): https://learn.microsoft.com/en-us/dotnet/standard/serialization/binaryformatter-security-guide
- Secure coding guidelines: https://learn.microsoft.com/en-us/dotnet/standard/security/secure-coding-guidelines
- Cryptographic services: https://learn.microsoft.com/en-us/dotnet/standard/security/cryptographic-services
- Regras de segurança dos analyzers: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/security-warnings
- Categorias/AnalysisMode: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/categories
- NuGet — supply chain: https://learn.microsoft.com/en-us/nuget/concepts/security-best-practices
- NuGet Audit: https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages
- Package Source Mapping: https://learn.microsoft.com/en-us/nuget/consume-packages/package-source-mapping
