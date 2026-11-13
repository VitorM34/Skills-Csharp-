---
name: aspnet-signalr
description: Implementar e revisar comunicação em tempo real com ASP.NET Core SignalR - hubs, clientes, transports (WebSockets/SSE/long polling), usuários e grupos, hubs tipados, streaming, autenticação/autorização, CORS, escala (sticky sessions, backplane Redis, Azure SignalR Service), configuração de timeouts, hub filters, hospedagem em background services. Use quando o usuário pedir chat/notificações/atualizações em tempo real ou revisar um hub. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# SignalR — tempo real no ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Autenticação geral: `aspnet-authentication-authorization`; CORS: `aspnet-web-security`; background: `aspnet-hosted-services`.

## O que é e quando usar
Comunicação **em tempo real** servidor→cliente (e cliente→servidor): apps com **atualizações de alta frequência** (jogos, redes sociais, votação, leilões, mapas/GPS) e **notificações** (chat, e-mail, alertas). **Transports** (fallback gracioso): **WebSockets** (preferido), Server-Sent Events, **Long Polling**; o SignalR escolhe o melhor disponível. Protocolos de mensagem: **JSON** (padrão) e **MessagePack**.

## Hubs
- Registre com `builder.Services.AddSignalR()` e mapeie com `app.MapHub<ChatHub>("/chat")`. O servidor define métodos chamados pelos clientes e os clientes definem métodos chamados pelo servidor; também há comunicação **indireta** cliente-a-cliente mediada pelo hub.
- `Context` (`HubCallerContext`): `ConnectionId`, `User`, `UserIdentifier` (por padrão `ClaimTypes.NameIdentifier`); `Clients` (todos, caller, outros, grupos, usuários); **hubs tipados** `Hub<IChatClient>`: verificação em **compilação** dos métodos de cliente (desabilita `SendAsync`); o sufixo `Async` **não** é removido dos nomes. **Client results**: o servidor pode pedir um resultado ao cliente. Nome do método do hub personalizável (`[HubMethodName]`).
- **Hubs são transitórios** (nova instância por invocação): não guarde estado em campos.

## Usuários e grupos
- **Groups** = coleção de conexões com nome; **forma recomendada** de enviar a uma ou várias conexões (gerenciado pela aplicação; uma conexão pode estar em vários grupos). **Grupos NÃO são recurso de segurança**: para proteger recursos use autenticação/autorização (claims têm expiração/revogação que grupos não têm); só adicione o usuário ao grupo quando as credenciais valerem para ele.

## Autenticação e autorização
- Autentique **no handshake** (cookie ou **bearer token** — navegadores usam query string para token em WebSockets/SSE; cliente .NET com `AccessTokenProvider`). **Se o token expira durante a conexão, por padrão a conexão continua**; `LongPolling` e `ServerSentEvents` falham nas requisições seguintes sem novo token; use **`CloseOnAuthenticationExpiration`** para fechar ao expirar.
- **Mudanças de usuário/roles durante a conexão**: `Context.User` mantém o principal **em cache** do início; `[Authorize(Roles = "Editor")]` em método do hub continua avaliando contra esse principal. **Faça checagens de autorização nos métodos do hub contra dados atuais** (roles/claims do banco) em vez de depender só do principal em cache.
- `[Authorize]` no hub/método; hub filters também podem aplicar políticas (ver abaixo).

## Segurança (CORS etc.)
- Navegador em outro domínio exige **CORS** habilitado: **origens específicas** (qualquer origem **não é seguro nem recomendado**); métodos **GET, POST e DELETE** permitidos (DELETE limpa conexões do Long Polling); **credenciais permitidas** (necessário para sticky sessions por cookie, mesmo sem autenticação). CORS pode ser aplicado **só nos endpoints dos hubs**.
- Valide entradas do cliente como em qualquer API; não confie em dados do cliente.

## Streaming
Métodos de hub podem retornar **`IAsyncEnumerable<T>`** (simples: método async iterator; aceita `CancellationToken` disparado quando o cliente cancela a assinatura) ou `ChannelReader<T>` (servidor→cliente); **client-to-server streaming** também suportado. Async iterators evitam problemas comuns de canais. Clientes: .NET, JavaScript, Java, Swift.

## Escala e hospedagem
- **Sticky sessions (session affinity)** são necessárias em server farm: o **mesmo processo** do servidor deve tratar todas as requisições de uma conexão. Exceções: clientes **só WebSockets** com **`SkipNegotiation`**, etc. Em **todos os outros cenários (inclusive com backplane Redis)**, configure sticky sessions.
- **Scale out:** cada servidor só conhece suas conexões; **sem backplane**, mensagem "para todos" chega só aos clientes daquele servidor. Soluções: **Azure SignalR Service** (gerencia as conexões; cada servidor mantém poucas conexões com o serviço) ou **backplane Redis**. Limites de **conexões TCP**/recursos do servidor; ver doc de escala.
- **Chamar o hub de fora** (controllers, background services): injete `IHubContext<THub>` (ver *hubcontext*); **background services** podem hospedar hubs (`AddSignalR` + `MapHub`).

## Configuração
Serialização (JSON: camelCase por padrão; `AddJsonProtocol`; MessagePack), opções do servidor: **`KeepAliveInterval`** e **`ClientTimeoutInterval`** (padrão 30 s; **recomendado o dobro do keep-alive**: o servidor considera o cliente desconectado sem mensagem nesse intervalo), **`HandshakeTimeout`** (15 s; só altere com latência severa), `MaximumReceiveMessageSize` etc. (ver doc).

## Hub filters
Aplicáveis **globalmente ou por hub** (ordem de adição; **globais antes dos locais**); para **pular** a invocação, lance **`HubException`** em vez de chamar `next` (o cliente recebe erro se esperava resultado); escreva lógica genérica usando **atributos** nos métodos em vez de comparar nomes; registre o filtro como singleton se mantiver dados.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Hub com `[Authorize]` ausente em endpoints sensíveis; token em query string sem HTTPS | Alta |
| 2 | Grupo usado como controle de acesso (sem autorização) | Alta |
| 3 | Autorização baseada só no `Context.User` em cache quando roles mudam | Média |
| 4 | CORS com `AllowAnyOrigin`; métodos/credenciais incompletos | Alta |
| 5 | Várias instâncias sem sticky sessions/backplane/Azure SignalR | Alta |
| 6 | Estado em campos do hub (transitório) | Alta |
| 7 | Streaming sem `CancellationToken` | Média |
| 8 | Timeouts/keep-alive inconsistentes entre cliente e servidor | Média |
| 9 | Enviar a `Clients.All` dados por usuário/privados | Alta |

## Fontes oficiais
- Overview: https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction
- Hubs: https://learn.microsoft.com/en-us/aspnet/core/signalr/hubs
- Users and groups: https://learn.microsoft.com/en-us/aspnet/core/signalr/groups
- Authentication and authorization: https://learn.microsoft.com/en-us/aspnet/core/signalr/authn-and-authz
- Security (CORS): https://learn.microsoft.com/en-us/aspnet/core/signalr/security
- Streaming: https://learn.microsoft.com/en-us/aspnet/core/signalr/streaming
- Hosting and scaling: https://learn.microsoft.com/en-us/aspnet/core/signalr/scale
- Configuration: https://learn.microsoft.com/en-us/aspnet/core/signalr/configuration
- Hub filters: https://learn.microsoft.com/en-us/aspnet/core/signalr/hub-filters
- Background services: https://learn.microsoft.com/en-us/aspnet/core/signalr/background-services
