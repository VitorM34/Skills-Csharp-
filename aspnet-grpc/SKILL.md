---
name: aspnet-grpc
description: Implementar e revisar gRPC no ASP.NET Core/.NET - contrato .proto, serviços (unary, server/client/bidirectional streaming), cliente .NET (GrpcChannel, client factory), deadlines e cancelamento, retries, tratamento de erros (RpcException, rich errors), segurança (TLS, autenticação, mensagens 4 MB), desempenho (reuso de canais), versionamento do .proto, gRPC-Web e JSON transcoding. Use quando o usuário pedir comunicação entre serviços com gRPC ou revisar serviços/clientes gRPC. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# gRPC em .NET

Só afirmar o que a doc oficial diz (fontes no fim). Escolha de comunicação entre serviços: `dotnet-distributed-patterns`. Resiliência: `dotnet-httpclient-resilience`.

## Quando usar (doc "Compare gRPC with HTTP APIs")
- **Fortes:** desempenho (**Protobuf** binário, rápido e pequeno), **geração de código**, especificação estrita, **streaming**, **deadlines/timeouts e cancelamento**. **Cenários:** microsserviços (baixa latência, alto throughput), comunicação ponto a ponto em tempo real (streaming bidirecional), ambientes poliglotas, redes limitadas, **IPC** (Unix domain sockets/named pipes).
- **Fracos:** **sem suporte direto em navegador** (exige HTTP/2 com controle que navegadores não dão): use **gRPC-Web** (cliente gRPC-Web gerado) ou **gRPC JSON transcoding** (.NET 7+; expõe os serviços como APIs REST/JSON anotando o `.proto`); mensagens **não legíveis por humanos**. Contrato **obrigatório** (`.proto`) × OpenAPI opcional.

## Contrato e geração
- **Contract-first**: o `.proto` (Protocol Buffers como IDL) define mensagens e serviços. `<Protobuf Include="..." GrpcServices="Server|Client|Both|None">` gera as classes (base de serviço e/ou cliente). Pacote `Grpc.Tools` é necessário em servidor e cliente; **`Grpc.AspNetCore`** (metapacote) já o inclui; em clientes referencie `Grpc.Tools` com `PrivateAssets="All"` (não é necessário em runtime).
- gRPC **não faz binding** de partes da requisição em argumentos distintos (como actions): **um único objeto de mensagem** por método; vários valores = vários campos.

## Serviços (`Grpc.AspNetCore`)
- Implemente a classe gerada `Greeter.GreeterBase` e registre com `app.MapGrpcService<GreeterService>()`; a base padrão devolve `UNIMPLEMENTED`.
- **Tipos:** unary, **server streaming** (cliente não envia mais mensagens após iniciar; streams contínuos terminam por cancelamento do cliente: use `ServerCallContext.CancellationToken`), **client streaming**, **bidirecional**. Headers via `ServerCallContext.RequestHeaders`.
- **Multi-thread em streaming:** `IAsyncStreamReader`/`IServerStreamWriter` **só podem ser usados por uma thread por vez** (sem `MoveNext`/`WriteAsync` simultâneos). Tarefas de fundo que usam o stream **não devem continuar após a chamada terminar**.

## Cliente
- `GrpcChannel.ForAddress("https://...")` (TLS conforme o esquema `https`; o canal e o serviço precisam ter a **mesma segurança**). **Reuse o canal** (multiplexa chamadas na conexão HTTP/2; criar canal por chamada aumenta muito o tempo por roundtrips de conexão). **Clientes gRPC são leves** e não precisam de cache. Em ASP.NET Core prefira o **gRPC client factory** (integra com `HttpClientFactory`): handlers, **interceptors** (por padrão uma instância compartilhada; `InterceptorScope.Client` para escopo por cliente), **call credentials**, **propagação de deadline e cancelamento** (`EnableCallContextPropagation`).
- **Sempre assíncrono** (`await`); métodos bloqueantes/`Task.Result` causam starvation de threads.
- **Concorrência de conexão:** conexões HTTP/2 têm limite de **streams concorrentes** (geralmente 100); **não é recomendado aumentar o limite**; para alta concorrência, vários canais/conexões. `ServerGarbageCollection` só vale em **clientes não servidores** (ASP.NET já usa server GC).

## Deadlines, cancelamento e retries
- **Deadline**: o cliente define quanto espera; ao exceder, a chamada é **cancelada**. **Não há deadline padrão** (chamadas sem limite): **configure sempre**; evita serviços travados esgotando recursos. No servidor, a requisição HTTP é abortada e `ServerCallContext.CancellationToken` dispara, **mas o método continua até terminar**: passe o token a todas as chamadas async. **Propague deadlines** em chamadas aninhadas (client factory com `EnableCallContextPropagation`).
- **Retries** (`Grpc.Net.Client` ≥ 2.36.0): `RpcException` com detalhes; política por método (`MethodConfig`, `RetryPolicy`: `MaxAttempts` (limite do canal `MaxRetryAttempts` = 5), `InitialBackoff`, `BackoffMultiplier`, `RetryableStatusCodes`); atraso **aleatório** entre 0 e o backoff atual. **Streaming** server/bidirecional **não faz retry depois da 1ª mensagem recebida** (refaça manualmente). Retry só em chamadas seguras/idempotentes (ver `dotnet-distributed-patterns`).

## Erros
- Servidor sempre retorna um **status** (`OK` ao concluir). Lance `RpcException` com `StatusCode` adequado (`INVALID_ARGUMENT` para dados faltantes). Cliente trata `RpcException` (falha no servidor com código, ou erro interno como `UNAVAILABLE`). **Rich error handling:** `Google.Rpc.Status` com `details` (`Any`; use os payloads padrão do modelo de erro do Google); erros vão em **headers**, limite típico de **8 KB**.

## Segurança
- **Só escute e responda em portas seguras (TLS)**; proxy de terminação TLS é opção, pesando o risco do tráfego sem TLS na rede privada.
- **Exceções:** por padrão **não** envia detalhes ao cliente (mensagens de exceção são sensíveis); `EnableDetailedErrors` só em dev/teste.
- **Tamanho de mensagem:** entrada limitada a **4 MB** por padrão (saída sem limite).
- **Autenticação:** middleware padrão do ASP.NET Core (`UseAuthentication`/`UseAuthorization` após `UseRouting`); **bearer token** via `CallCredentials` (**só são aplicadas se o canal usar TLS**); **certificado de cliente** com `Microsoft.AspNetCore.Authentication.Certificate`; **Windows Authentication não funciona** (HTTP/2 não suporta). **Por padrão usuários não autenticados podem chamar todos os métodos**: aplique `[Authorize]` (no serviço ou método).

## Versionamento do `.proto`
- **Não quebra:** adicionar campo ao request (servidor precisa funcionar sem ele), adicionar valor a enum (clientes antigos devem tolerar). **Quebra binária** (cliente precisa atualizar): remover campo (**não reutilize o número**; use `reserved`). **Quebra de protocolo:** renomear campo **só quebra com conteúdo JSON** (Protobuf usa o número do campo). Também há quebras de **comportamento**.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Cliente cria `GrpcChannel` por chamada | Alta |
| 2 | Chamadas sem deadline; token de cancelamento do servidor não repassado | Alta |
| 3 | Serviço sem `[Authorize]`/sem TLS; `EnableDetailedErrors` em produção | Alta |
| 4 | Chamadas bloqueantes (`.Result`) a clientes gRPC | Alta |
| 5 | Retry em operações não idempotentes; streaming esperando retry após mensagens | Média |
| 6 | Reutilização de número de campo removido; mudança incompatível sem versionamento | Alta |
| 7 | Streams escritos/lidos por várias threads | Alta |
| 8 | Navegador chamando gRPC direto (precisa gRPC-Web/transcoding) | Média |
| 9 | Mensagens grandes sem streaming (limite de 4 MB) | Média |

## Fontes oficiais
- gRPC no ASP.NET Core (índice): https://learn.microsoft.com/en-us/aspnet/core/grpc/
- Comparação com APIs HTTP: https://learn.microsoft.com/en-us/aspnet/core/grpc/comparison
- Serviços e métodos: https://learn.microsoft.com/en-us/aspnet/core/grpc/services
- Cliente .NET: https://learn.microsoft.com/en-us/aspnet/core/grpc/client
- Client factory: https://learn.microsoft.com/en-us/aspnet/core/grpc/clientfactory
- Deadlines e cancelamento: https://learn.microsoft.com/en-us/aspnet/core/grpc/deadlines-cancellation
- Retries: https://learn.microsoft.com/en-us/aspnet/core/grpc/retries
- Tratamento de erros: https://learn.microsoft.com/en-us/aspnet/core/grpc/error-handling
- Segurança: https://learn.microsoft.com/en-us/aspnet/core/grpc/security
- Autenticação/autorização: https://learn.microsoft.com/en-us/aspnet/core/grpc/authn-and-authz
- Desempenho: https://learn.microsoft.com/en-us/aspnet/core/grpc/performance
- Versionamento: https://learn.microsoft.com/en-us/aspnet/core/grpc/versioning
- JSON transcoding: https://learn.microsoft.com/en-us/aspnet/core/grpc/json-transcoding
- gRPC-Web: https://learn.microsoft.com/en-us/aspnet/core/grpc/grpcweb
