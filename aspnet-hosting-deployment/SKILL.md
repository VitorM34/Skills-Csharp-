---
name: aspnet-hosting-deployment
description: Hospedar, configurar e revisar o deploy de apps ASP.NET Core - Kestrel (endpoints, URLs, HTTPS, limites), quando usar reverse proxy (Nginx, IIS, Apache, YARP), Forwarded Headers (X-Forwarded-For/Proto/Host, KnownProxies, loop de HTTPS redirect), host filtering (AllowedHosts), PathBase, containers (Dockerfile multi-stage, imagens aspnet/sdk, porta 8080, usuário não-root, dotnet publish /t:PublishContainer). Use quando o usuário pedir deploy, Docker, proxy reverso, portas/HTTPS em produção ou revisar configuração de hospedagem. Based on official Microsoft Learn docs (ASP.NET Core 10 / .NET SDK containers).
---

# Hospedagem e deploy (Kestrel, proxy reverso, containers)

Só afirmar o que a doc oficial diz (fontes no fim). HTTPS/HSTS/CORS: `aspnet-web-security`. Middleware/ordem: `aspnet-middleware-pipeline`. Health checks: `aspnet-health-checks`. Configuração/segredos: `aspnet-configuration-options`. IIS/Nginx/Apache/Windows Service/Azure: ver páginas em *host-and-deploy* (não detalhadas aqui).

## Kestrel
- **Servidor recomendado** e padrão dos templates (cross-platform, HTTP/1.1, HTTP/2, HTTP/3, WebSockets). **Pode ser usado sozinho (edge) ou atrás de reverse proxy: ambas são configurações suportadas.** macOS é suportado para **desenvolvimento/CI**, não para produção.
- **Endpoints** (endereço + protocolo): por `ASPNETCORE_URLS`, `--urls`, chave `urls`, `UseUrls`, `WebApplication.Urls`, seção `Kestrel:Endpoints` no `appsettings.json` (recarregável; endpoints removidos/alterados têm **5 s** para concluir requisições) ou código (`ConfigureKestrel`). Sem configuração, Kestrel usa `http://localhost:5000`; portas aleatórias 5000–5300 / 7000–7300 vêm do `launchSettings.json` (**só desenvolvimento**). `0.0.0.0`/`[::]` = todas as interfaces; host que não é IP nem `localhost` vira **wildcard**.
- **HTTPS em URL prefixes só funciona se houver certificado padrão** configurado (`Certificates:Default`, `HttpsDefaultCert` ou código); em dev usa-se o **certificado de desenvolvimento** (`dotnet dev-certs https --trust`, Windows/macOS).
- **Limites** (`ConfigureKestrel` → `Limits`): `MaxRequestBodySize` (preferir `[RequestSizeLimit]` por action), `MaxConcurrentConnections`, `KeepAliveTimeout`, `RequestHeadersTimeout`, `MinRequestBodyDataRate`/`MinResponseDataRate` (defesa contra clientes lentos), limites HTTP/2 (`MaxStreamsPerConnection`...). Atrás do **ASP.NET Core Module/IIS out-of-process**, o limite de corpo é do IIS (o do Kestrel é desabilitado). Timeouts de keep-alive/headers **não são aplicados com debugger anexado**.
- Sem proxy, **não compartilhe IP:porta entre processos**; Kestrel responde a **todo** tráfego da porta independentemente do `Host`.

## Reverse proxy
- Benefícios (doc): limita superfície exposta, defesa em profundidade, integra com infraestrutura, simplifica **load balancing e TLS** (só o proxy precisa do certificado público; interno pode ser HTTP ou HTTPS — HTTPS interno é mais seguro mas tem **overhead significativo**).
- **⚠ Atrás de reverse proxy, host filtering é obrigatório.**
- **Host filtering**: Kestrel **não valida o header `Host`**. Defina `AllowedHosts` (lista separada por `;`, sem porta) no `appsettings.json`; vem **desabilitado** por padrão. `ForwardedHeadersOptions.AllowedHosts` é para quando o proxy **não preserva** o `Host` (usa `X-Forwarded-Host`); `AllowedHosts` do host filtering é para Kestrel edge ou `Host` encaminhado direto.

## Forwarded Headers (proxy/load balancer)
- Proxies escondem **esquema original (HTTPS→HTTP)** e **IP do cliente**; isso afeta redirects, autenticação, geração de links, políticas e geolocalização. Headers: `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host` (CVE-2018-0787: proxy deve validar/restringir Host) e `X-Forwarded-Prefix`. O `ForwardedHeadersMiddleware` preenche `RemoteIpAddress`, `Request.Scheme`, `Request.Host`, `Request.PathBase` (valores antigos vão para `X-Original-*`).
- **Fora de IIS (out-of-process) o middleware NÃO vem habilitado**: chame `UseForwardedHeaders` com `ForwardedHeaders = XForwardedFor | XForwardedProto` (**padrão é `None`**), **antes** dos demais middlewares (pode ficar depois de diagnóstico/erros, mas **antes de `UseHsts`**).
- Padrões: **um** proxy, só loopback em `KnownProxies`/`KnownNetworks`, `ForwardLimit = 1` (processa só o valor mais à direita). **Configure `KnownProxies`/`KnownNetworks`** para a sua rede; `ForwardLimit = null` só com known proxies configurados. Se o proxy usa outros nomes de header, ajuste `ForwardedForHeaderName`/`ForwardedProtoHeaderName`.
- **Loop infinito:** `UseHttpsRedirection` + `UseHsts` atrás de proxy que termina TLS (Azure Linux App Service, VM Linux, qualquer proxy que não seja IIS) sem esquema encaminhado ⇒ loop de redirect; **OAuth/OIDC também falham** (redirects errados). Solução: habilitar forwarded headers; atalho: variável **`ASPNETCORE_FORWARDEDHEADERS_ENABLED=true`** — **usa configurações pensadas para nuvem e NÃO restringe IPs (`KnownProxies`)**.
- **PathBase:** proxy que mantém prefixo (`/foo/api/1`) → `app.UsePathBase("/foo")` **antes** de `UseRouting`; se o proxy remove o prefixo, defina `Request.PathBase`.
- Certificado de cliente atrás de proxy: `UseCertificateForwarding` **antes** de `UseAuthentication`.

## Containers
- **Duas opções oficiais:** (1) **Dockerfile multi-stage** (build com `mcr.microsoft.com/dotnet/sdk:10.0`; runtime com `mcr.microsoft.com/dotnet/aspnet:10.0` — imagem menor, "otimizada para produção", só binários necessários); (2) **SDK container build** sem Dockerfile e sem Docker (SDK ≥ 8.0.200 já inclui): `dotnet publish --os linux --arch x64 /t:PublishContainer`. Docker/Podman só são necessários para **rodar** a imagem local; também dá para gerar **tarball** (`ContainerArchiveOutputPath`, ótimo para scan de segurança) ou publicar direto em **registry** (`ContainerRegistry`, autenticação via `docker login`/`DOCKER_CONFIG`). Preferir **target** (`/t:PublishContainer`) a profile.
- **Porta:** nas imagens atuais o ASP.NET escuta na **8080** (exemplo oficial: `docker run -p <porta>:8080`). `ContainerPort` é inferido de `ASPNETCORE_URLS`, `ASPNETCORE_HTTP_PORTS`, `ASPNETCORE_HTTPS_PORTS`.
- **Usuário não-root:** `ContainerUser` — o padrão em .NET 8+ com imagens Microsoft no Linux é o usuário **`app` (rootless)**; "rodar como não-root é boa prática de segurança"; mudar o usuário afeta permissões de arquivo; `root` só se necessário. Propriedades úteis: `ContainerRepository`, `ContainerImageTag`, `ContainerBaseImage`, `ContainerFamily` (ex.: `alpine`), `ContainerRuntimeIdentifiers` (multi-arch), `ContainerEnvironmentVariable`, `ContainerLabel`.
- Container pequeno: ver página de GC em containers (`performance/memory`). Segredos **não** vão na imagem: variáveis de ambiente/secret store (ver `efcore-dbcontext-connection`, `aspnet-configuration-options`). HTTPS em Docker Compose: tem tutorial próprio (`security/docker-compose-https`).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Atrás de proxy sem `UseForwardedHeaders`/`ASPNETCORE_FORWARDEDHEADERS_ENABLED` (esquema errado, loop de redirect, OIDC quebrado) | Alta |
| 2 | Forwarded headers sem `KnownProxies/KnownNetworks` em rede não confiável (spoof de IP) | Alta |
| 3 | Reverse proxy sem `AllowedHosts` | Alta |
| 4 | `UseForwardedHeaders` depois de `UseHsts`/auth; `UsePathBase` depois de `UseRouting` | Média |
| 5 | Container rodando como root sem necessidade; segredos na imagem/Dockerfile | Alta |
| 6 | Imagem final com SDK (sem multi-stage) | Média |
| 7 | Porta/`ASPNETCORE_URLS` inconsistente com `EXPOSE`/mapeamento (8080) | Média |
| 8 | Limites do Kestrel padrão em endpoint público (corpo, data rate, timeouts) sem revisão | Média |
| 9 | Dependência do `launchSettings.json` em produção; certificado de dev em produção | Alta |
| 10 | Produção em macOS | Baixa |

## Fontes oficiais
- Kestrel: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel
- Endpoints: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints
- Options/limits: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/options
- Reverse proxy: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/when-to-use-a-reverse-proxy
- Host filtering: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/host-filtering
- Proxy/load balancer: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/proxy-load-balancer
- Docker + ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/docker/building-net-docker-images
- Containerize with dotnet publish: https://learn.microsoft.com/en-us/dotnet/core/containers/sdk-publish
- Container publish reference: https://learn.microsoft.com/en-us/dotnet/core/containers/publish-configuration
- Host and deploy (índice): https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/
