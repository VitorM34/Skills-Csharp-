---
name: dotnet-dapper-adonet
description: Acesso a dados SQL sem EF Core com ADO.NET (Microsoft.Data.SqlClient) e Dapper - quando preferir micro-ORM, conexões e pooling (abrir tarde/descartar cedo, Max Pool Size), parâmetros e prevenção de SQL injection (SqlParameter, DynamicParameters, listas, DbString, literal replacements), Query/Execute/multi-mapping/QueryMultiple/stored procedures, buffered vs unbuffered, async com CancellationToken, transações locais, retry de erros transitórios, criptografia (Encrypt/TrustServerCertificate), segurança da connection string e migração de System.Data.SqlClient. Use quando o usuário pedir queries de leitura rápidas (CQRS), SQL manual, stored procedures, ou revisar código ADO.NET/Dapper. Based on Microsoft Learn (SqlClient/ADO.NET, guia de microsserviços) e documentação oficial do Dapper (terceiros).
---

# ADO.NET (SqlClient) e Dapper

**Proveniência:** **[SQLCLIENT]** documentação oficial da Microsoft do `Microsoft.Data.SqlClient` (ADO.NET para SQL Server/Azure SQL); **[MS-ARCH]** guia oficial de microsserviços (Dapper na camada de consultas); **[DAPPER]** README oficial do projeto **Dapper** (biblioteca de terceiros — a Microsoft só a cita como exemplo de micro-ORM). **Provedores de outros bancos** (Npgsql, MySQL etc.) **não foram lidos**: os princípios de ADO.NET valem, mas confira a doc do provider. Convenções minhas: **CONVENÇÃO**.
Ligações: `efcore-sql-performance` (SQL bruto no EF), `dotnet-ddd-tactical`/`dotnet-distributed-patterns` (CQRS), `dotnet-security-review` (SQL injection), `aspnet-configuration-options` (connection string), `csharp-async-await`, `dotnet-service-implementation`, `dotnet-local-dev-containers` (banco real nos testes), `dotnet-dto-review`.

## Quando usar (e quando não)
- **[MS-ARCH]** Em CQRS simplificado, o **lado de consulta** pode usar um **micro-ORM como o Dapper** consultando o banco direto e devolvendo **ViewModels/DTOs** sob medida; consultas são idempotentes e **ficam fora das restrições do DDD** (agregados). O **lado de comandos** (mudança de estado, transações, regras) normalmente usa o domínio + EF Core (`dotnet-ddd-tactical`, `efcore-saving-concurrency`). A doc oficial prefere DTOs **explícitos** ao `dynamic`.
- **CONVENÇÃO:** use EF Core por padrão; vá de ADO.NET/Dapper em **leituras críticas de desempenho**, relatórios, SQL já pronto/stored procedures, ou quando o EF não expressa a consulta. Coloque o SQL em um **lugar único** (classe de query/repositório), nunca espalhado em controllers (`dotnet-service-implementation`). Misturar EF e Dapper no mesmo app é comum; quanto a compartilhar conexão/transação entre os dois, **não li a doc** — trate como risco e teste.

## Provider e conexão [SQLCLIENT]
- **`Microsoft.Data.SqlClient` é o provider suportado para novos recursos do SQL Server em .NET**; `System.Data.SqlClient` é o antigo. Migrar: trocar `using System.Data.SqlClient` por `using Microsoft.Data.SqlClient` (não troque `System.Data`/`System.Data.Common`); **não passe objetos de um provider para código do outro**; migre um app/biblioteca por vez. **Atenção aos defaults mais seguros:** `Encrypt=true` a partir da 4.0 (antes `false`) e validação de certificado conforme `TrustServerCertificate` quando o servidor força criptografia — conexões antigas para servidor com certificado não confiável **passam a falhar** (corrija o certificado, não desligue a validação).
- **Padrão oficial:** *"Open late, dispose early"*:
```csharp
await using var connection = new SqlConnection(connectionString);
await connection.OpenAsync(ct);
using var command = new SqlCommand(sql, connection);
```
**Não mantenha um `SqlConnection` aberto globalmente.** `Close`/`Dispose`/`DisposeAsync` devolve a conexão ao **pool** (que reseta o estado da sessão ao reutilizar). **CONVENÇÃO (ASP.NET Core):** registre uma fábrica (ex.: `IDbConnectionFactory`) como singleton que só **cria** conexões; quem consulta abre/descarta por operação.
- **Pooling (padrão ligado):** `Max Pool Size` = **100**, `Min Pool Size` = 0; com o pool esgotado, novas aberturas **esperam** e falham após `Connect Timeout`. **Antes de aumentar `Max Pool Size`:** confirme que **toda conexão e reader é descartado em todos os caminhos** (vazamento é a causa típica) e que o banco aguenta `Max Pool Size × pools × instâncias`. `Min Pool Size > 0` só com medição (atrapalha serverless/scale-to-zero). O pool **não valida a conexão a cada checkout** (custo de round trip).
- **Chave do pool = a connection string exata** (inclusive `Application Name`, modo de autenticação, opções de criptografia): **use uma única string canônica**; **não coloque valores por requisição** em `Application Name`/`Workstation ID`; **não crie credenciais/callbacks de token novos a cada requisição** (fragmenta os pools).

## Segurança da conexão [SQLCLIENT]
- **Criptografia:** defaults `Encrypt=Mandatory` e `TrustServerCertificate=false`. **Criptografar sem validar o certificado não protege contra adversário no meio.** Modos: `Optional/false` (só o login é criptografado), `Mandatory`, **`Strict`** (TDS 8.0: TLS antes do TDS; `TrustServerCertificate` não contorna). Em conexão remota, peça explicitamente `Encrypt=true;TrustServerCertificate=false` com certificado que o cliente consiga validar. **Nunca `TrustServerCertificate=true` em produção** como atalho.
- **Credenciais:** prefira **autenticação integrada/identidade** (sem senha na string); conta com **privilégio mínimo**; `Persist Security Info=false` (padrão); **não embuta connection string no código** (pode ser lida por disassembler); proteja arquivos de configuração (`aspnet-configuration-options`, `dotnet-security-review`).

## Parâmetros e SQL injection [SQLCLIENT/DAPPER]
- **Regra de ouro (Microsoft):** "use `SqlParameter` **em vez de concatenar ou interpolar** valores no SQL" — protege contra injection e preserva o tipo do banco. **Nunca** `$"... WHERE Name = '{nome}'"`.
- **SqlClient:** prefira `Parameters.Add("@x", SqlDbType.Int).Value = ...` **com tipo (e `Size`/`Precision`/`Scale`) explícito** — evita conversões implícitas e planos diferentes quando o tamanho da string muda; `AddWithValue` infere o tipo do valor (só quando estável); **não passe `null` do C# ao `AddWithValue`** — defina o tipo e atribua `DBNull.Value`.
- **Dapper:** parâmetros por **objeto anônimo/POCO** (`new { A = 1, B = "b" }` → `@A`, `@B`), `Dictionary<string,object>` ou **`DynamicParameters`** (monta SQL dinâmico **mantendo parâmetros**, com `DbType` e direção output/return). **Listas:** `where Id in @Ids` com `IEnumerable` é **expandido em parâmetros** automaticamente. **Literal replacements** `{=Admin}` só para `bool`/numérico (não vai como parâmetro; plano melhor/índices filtrados; "usar com moderação e após testar"). **`DbString`** (`IsAnsi`, `IsFixedLength`, `Length`) para colunas **varchar**: "no SQL Server é crucial usar unicode ao consultar unicode e ANSI ao consultar não-unicode" (evita conversão de coluna e perda de índice).
- **Identificadores dinâmicos** (nome de coluna/tabela, `ORDER BY`) **não são parametrizáveis**: use **lista de permissão** (CONVENÇÃO, mesma lógica do `FromSqlRaw` — `efcore-sql-performance`, `dotnet-security-review`).

## Dapper — operações [DAPPER]
- Extensões sobre `DbConnection`: `Execute` (insert/update/delete; **com coleção executa várias vezes**, ex.: carga em lote), `Query<T>` (várias linhas), `QuerySingle<T>`/`First`/`...OrDefault`; há versões **síncronas e assíncronas**; `Query` sem tipo devolve `dynamic` (prefira tipado).
- **Buffered (padrão):** lê tudo e devolve — minimiza locks e tempo de rede; **`buffered: false`** para consultas enormes (menos memória, carrega sob demanda).
- **Multi-mapping:** `Query<Post, User, Post>(sql, (post, user) => { post.Owner = user; return post; }, splitOn: "Id")` — assume colunas `Id`/`id` para dividir a linha; use `splitOn` se for diferente. **`QueryMultiple`** lê vários result sets (`multi.Read<T>()`). **Stored procedures:** `commandType: CommandType.StoredProcedure`; output/return via `DynamicParameters`. **`GetRowParser`** para tipos diferentes por linha.
- Mapeamento por **nome de coluna ↔ propriedade**: crie DTOs explícitos para cada consulta (`dotnet-dto-review`).

## Async, cancelamento e concorrência [SQLCLIENT]
- Use `OpenAsync`/`ExecuteReaderAsync`... **de ponta a ponta** com **`CancellationToken`** (ex.: `CancellationTokenSource` com timeout finito) — `csharp-async-await`; nada de `.Result`/`.Wait()`.
- **Async não torna comando/reader seguro para uso concorrente** nem reduz o tempo de execução no servidor: **`await` cada operação antes de reutilizar o mesmo objeto**; **não use o mesmo `SqlConnection`/reader em tarefas paralelas** (uma conexão por tarefa).
- **Streaming** (`GetStream`, `GetTextReader`...): para valores grandes (binários, texto, XML/JSON) sem carregar tudo; conexão, comando, reader e destino devem permanecer vivos até terminar. **Paginação:** limite as linhas **na própria consulta** (não use `DataAdapter.Fill` com paginação, que traz o resultado inteiro).

## Transações e resiliência [SQLCLIENT]
- **Transação local:** `connection.BeginTransaction()` → **associe cada comando à transação** (`command.Transaction`) → `Commit()` ou `Rollback()` (em `catch`); o **escopo é a conexão**. A Microsoft nota que transações são mais eficientes **no servidor**: para uso intenso, considere **stored procedure** com `BEGIN TRANSACTION`. Não use `EnlistDistributedTransaction` para transação local. (Com Dapper, passe a transação aos comandos — a README lida não detalha isso: confira a API.)
- **Retry de falhas transitórias (SqlClient ≥ 3.0):** *retry logic* configurável — provedor exponencial com **jitter** que repete a lista interna de erros transitórios de **conexão** (`NumberOfTries = 5` = 1 tentativa + 4 retries; `MaxTimeInterval` limita **cada** atraso, não o total). Para **comandos**, atribua `SqlCommand.RetryLogicProvider` e use **`AuthorizedSqlCondition`** para permitir retry **só de comandos que podem ser repetidos com segurança** (idempotentes). **O provedor interno não repete comando quando há transação ativa**: se a falha transitória invalida a transação, **faça rollback e repita a transação inteira**, não só a instrução. `TransientErrors` customizado **substitui** a lista padrão. O EF Core tem estratégia própria (`dotnet-httpclient-resilience` para HTTP; EF em `efcore-saving-concurrency`).

## Observabilidade e testes
- SqlClient expõe **EventSource/contadores de eventos** (páginas *event-counters*/*diagnostic-counters* da doc; não detalhadas aqui) — ver `dotnet-observability`. Logue SQL **sem valores sensíveis** (`aspnet-logging`).
- **Teste contra o banco real** em container (`dotnet-local-dev-containers`, módulo `Testcontainers.MsSql`/`PostgreSql`) e valide mapeamento de colunas, parâmetros e planos; migrations/schema do teste precisam espelhar produção.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | SQL montado por concatenação/interpolação com entrada do usuário (em vez de parâmetros) | Alta |
| 2 | Identificador dinâmico (coluna/ORDER BY) vindo do cliente sem lista de permissão | Alta |
| 3 | `TrustServerCertificate=true`/`Encrypt=false` em produção; senha na connection string no repositório | Alta |
| 4 | `SqlConnection`/reader/command sem descarte em algum caminho (vazamento do pool); conexão global aberta | Alta |
| 5 | Mesma conexão/reader usado em tarefas paralelas | Alta |
| 6 | `.Result`/`.Wait()` em chamadas de banco; sem `CancellationToken`/timeout | Média |
| 7 | `AddWithValue` com strings/decimais variáveis ou `null` do C#; `varchar` consultado com parâmetro nvarchar (sem `DbString`) | Média |
| 8 | Aumento de `Max Pool Size` para "resolver" timeout sem checar vazamento/limite do banco; connection strings diferentes fragmentando pools | Média |
| 9 | Retry de comando não idempotente ou retry parcial dentro de transação | Média |
| 10 | Resultado enorme com `Query` buffered (memória) ou paginação feita em memória | Média |
| 11 | `dynamic`/`SELECT *` em consultas de produção em vez de DTO e colunas explícitas | Baixa |
| 12 | Ainda usando `System.Data.SqlClient` em código novo | Baixa |
| 13 | SQL espalhado por controllers/serviços sem camada de consulta | Baixa |

## Fontes
**[SQLCLIENT] Microsoft Learn — Microsoft.Data.SqlClient:** Comandos e parâmetros https://learn.microsoft.com/en-us/sql/connect/ado-net/configure-parameters · Pooling https://learn.microsoft.com/en-us/sql/connect/ado-net/sql-server-connection-pooling · Async https://learn.microsoft.com/en-us/sql/connect/ado-net/asynchronous-programming · Transações locais https://learn.microsoft.com/en-us/sql/connect/ado-net/local-transactions · Retry logic https://learn.microsoft.com/en-us/sql/connect/ado-net/configurable-retry-logic-sqlclient-introduction · Criptografia https://learn.microsoft.com/en-us/sql/connect/ado-net/encryption-and-certificate-validation · Migração https://learn.microsoft.com/en-us/sql/connect/ado-net/migrate-system-data-sql-client-to-microsoft-data-sql-client · Proteger connection info https://learn.microsoft.com/en-us/sql/connect/ado-net/protecting-connection-information · Streaming https://learn.microsoft.com/en-us/sql/connect/ado-net/sqlclient-streaming-support
**[MS-ARCH] CQRS com Dapper:** https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/cqrs-microservice-reads
**[DAPPER]** README oficial: https://github.com/DapperLib/Dapper
