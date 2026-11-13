---
name: dotnet-mongodb
description: Usar MongoDB em .NET com o driver oficial MongoDB.Driver (e noções do provider EF Core para MongoDB) - MongoClient singleton e DI, connection string/MongoClientSettings, pool, TLS/autenticação, POCOs e mapeamento BSON (ObjectId, Guid, DateTime, camelCase, campos extras), CRUD com Builders e LINQ3, bulk, índices, transações/sessões, change streams, logging e upgrade para v3. Use quando o usuário pedir MongoDB/Mongo em C#/.NET, IMongoCollection, repositórios Mongo, modelagem de documentos no .NET, ou ao revisar esse código.
---

# MongoDB em .NET (driver oficial)

**Proveniência:** documentação **oficial da MongoDB, Inc.** (não é Microsoft) — repositório `mongodb/docs-csharp` (.NET/C# Driver) marcado **[MDB]** e `mongodb/docs-entity-framework` (provider EF Core) marcado **[MDB-EF]**. **CONVENÇÃO** = recomendação desta skill, não da doc. **Atenção à defasagem:** a doc que li lista compatibilidade até driver **3.4** (NuGet está em **3.13.0**; `MongoDB.EntityFrameworkCore` **10.0.4**, enquanto a doc do provider que li chega a "What's New 9.0") — confirme comportamento na versão instalada. **Não li:** manual do servidor MongoDB (modelagem, sharding, replica set, políticas de índice/transação no servidor), Atlas Search/Vector Search, CSFLE/Queryable Encryption, GridFS, time series (só a existência), mecanismos de auth além de SCRAM (X.509, OIDC, AWS IAM, Kerberos, LDAP — só os títulos), Mongo Driver para Aspire. Para persistência relacional/EF Core clássica veja `efcore-querying`, `efcore-saving-concurrency`.
Ligações: `aspnet-configuration-options`, `dotnet-dependency-injection`, `csharp-async-await`, `csharp-linq`, `dotnet-observability`, `dotnet-serilog`, `dotnet-local-dev-containers`, `dotnet-integration-testing`, `dotnet-security-review`, `dotnet-ddd-tactical`, `dotnet-distributed-patterns`, `dotnet-dapper-adonet`.

## Quando MongoDB (CONVENÇÃO)
Documentos aninhados lidos/gravados como unidade, esquema flexível, agregados de DDD (`dotnet-ddd-tactical`). Para dados fortemente relacionais com junções/integridade referencial o relacional costuma servir melhor (`efcore-querying`, `efcore-saving-concurrency`). Mongo **não tem foreign keys** [MDB-EF]; integridade entre documentos é responsabilidade da aplicação.

## Cliente, conexão e DI [MDB]
- Dois ingredientes: **connection URI** e **`MongoClient`**. `new MongoClient("mongodb://host:27017/")`. Opções por URI (`?connectTimeoutMS=…&tls=true`), por `MongoClientSettings` (mais opções, checado em compilação; `MongoClientSettings.FromConnectionString(uri)` para partir de uma string) ou `MongoUrlBuilder`.
- **Reutilize o cliente**: a doc recomenda reaproveitar o `MongoClient` em vez de criar um por operação/sessão; ele **mantém o pool de conexões**. Registre **uma instância singleton** (`AddSingleton<IMongoClient>`; a doc de OData faz isso, e o tutorial ASP.NET Core instancia o cliente dentro de um serviço singleton). `IMongoClient`, `IMongoDatabase` e `IMongoCollection<T>` são **imutáveis**: configurar write concern etc. **devolve nova instância**.
```csharp
builder.Services.Configure<MongoSettings>(builder.Configuration.GetSection("MongoDB"));
builder.Services.AddSingleton<IMongoClient>(sp =>
    new MongoClient(sp.GetRequiredService<IOptions<MongoSettings>>().Value.ConnectionString));
builder.Services.AddSingleton(sp => sp.GetRequiredService<IMongoClient>()
    .GetDatabase(sp.GetRequiredService<IOptions<MongoSettings>>().Value.DatabaseName));
// coleção: db.GetCollection<Playlist>("playlists")
```
- **Connection string é segredo** (credenciais): user-secrets/variável de ambiente/secret store, nunca no repo (`aspnet-configuration-options`, `dotnet-security-review`).
- **Pool** [MDB] (`MongoClientSettings`/URI): `MaxConnectionPoolSize` padrão **100** (`maxPoolSize`), `MinConnectionPoolSize` 0, `MaxConnecting` 2, `MaxConnectionIdleTime` 10 min, `MaxConnectionLifeTime` 30 min, `ConnectTimeout` 30 s. Esgotado o pool, requisições **esperam**.
- **Server selection** pode ser customizado, mas a doc avisa de possível degradação de leitura/escrita — não mexa sem motivo.
- **Stable API**: versão fixada no cliente (não muda depois de criado); contra servidor que não a suporta, comandos falham.
- Troubleshooting de conexão (doc): confira host/porta (27017 padrão) e firewall (não abra porta sem certeza); `AuthenticationFailed` com SCRAM → a causa mais comum é connection string inválida; **usuário/senha com `: / ? # [ ] @` precisam de percent-encoding** (ex.: `HttpUtility.UrlEncode`).
- Retry de leitura/escrita: o driver tem `RetryReads`/`RetryWrites` em `MongoClientSettings` (aparecem nos exemplos da doc para desligar); o padrão **não confirmei** na doc lida.

## Segurança [MDB]
- **TLS**: o driver suporta só **TLS 1.2+**; conexão por DNS seedlist (`mongodb+srv://`) liga TLS por padrão. Desabilitar validação de certificado (`AllowInsecureTls` ou `tlsInsecure=true`) — a doc diz: **sempre `false` em produção**. Revogação de certificado não é verificada por padrão (comportamento do `SslStream`); no Windows, OCSP indisponível = *hard fail*.
- **Autenticação**: SCRAM-SHA-256 é o padrão do servidor ≥ 4.0 (SCRAM-SHA-1 antes). A doc tem páginas de X.509, OIDC, AWS IAM, Kerberos, LDAP (não li). `MONGODB-CR` foi removido no driver 3.0. Use usuário com **menor privilégio** por aplicação (CONVENÇÃO).
- **Injeção** (CONVENÇÃO — a doc do driver que li não trata o tema): monte filtros com `Builders<T>.Filter`/LINQ com valores tipados e **não** concatene entrada do usuário em JSON/`BsonDocument` de filtro; valide a entrada antes (`aspnet-validation`). Para o risco em si consulte o manual de segurança do MongoDB (não li).

## POCOs e mapeamento BSON [MDB]
- Doc recomenda **POCOs** (sem herdar de base de framework) por idiomaticidade e desempenho. O driver cria um *class map* automático casando **nome da propriedade = nome do campo**; **o tipo da propriedade deve combinar com o tipo do campo**.
- Atributos: `[BsonId]` (a propriedade `_id`; mais de uma → `DuplicateBsonMemberMapAttributeException`; `Id` e `_id` juntas → `BsonSerializationException`), `[BsonElement("nome")]` (nome do campo; também força incluir propriedade **somente leitura**), `[BsonRepresentation(BsonType.X)]` (tipo no BSON, ex.: `string` ↔ `ObjectId`), `[BsonIgnore]`, `[BsonIgnoreIfNull]`, `[BsonIgnoreIfDefault]` (útil no `_id` em `ReplaceOne`), `[BsonIgnoreExtraElements]` (campos do documento sem propriedade correspondente — sem isso, desserializar documento com campo extra **falha**), `[BsonDateTimeOptions(...)]`.
- **Nomes camelCase**: por padrão os campos usam o nome exato da propriedade (PascalCase). Para camelCase registre **uma vez no startup**: `ConventionRegistry.Register("CamelCase", new ConventionPack { new CamelCaseElementNameConvention() }, _ => true)` (a doc usa isso nos exemplos). Atenção: **`BsonDocument` em pipelines/filtros manuais ignora atributos/convenções** — nomes têm de bater com os do banco.
- `_id`: use `ObjectId` quando possível. `string` com `[BsonRepresentation(BsonType.ObjectId)]` e `[BsonId(IdGenerator = typeof(StringObjectIdGenerator))]` gera ObjectId. Para `Guid` o gerador `CombGuidGenerator` está na doc.
- **GUID** [MDB]: a doc diz para preferir `ObjectId`; se usar GUID, use **subtype 4 (`GuidRepresentation.Standard`)**, pois subtype 3 (legado) tem ordem de bytes diferente por driver (C#/Java/Python). Coleções antigas podem misturar 3 e 4 — o driver trata **por propriedade**. No **v3 só existe o modo V3**; `BsonBinaryData(Guid)` foi removido (use `BsonBinaryData.Create(Guid, GuidRepresentation)`); `ToGuid()` só para subtype 4.
- **DateTime**: armazenado em **UTC**; com `Kind = Local` o driver converte para UTC ao serializar; para campos só-data use `[BsonDateTimeOptions(DateOnly = true)]` (sem conversão de fuso). A doc tem seção para `DateOnly` customizado e dicionários (não li em detalhe).
- Documentos limitados a **16 MB** (use GridFS acima disso — não li).
- Polimorfismo: veja `serialization/polymorphic-objects` na doc (não li).

## CRUD [MDB]
```csharp
var col = db.GetCollection<Order>("orders");
await col.InsertOneAsync(order, cancellationToken: ct);                       // _id duplicado → MongoWriteException
var f = Builders<Order>.Filter.Eq(o => o.CustomerId, id) & Builders<Order>.Filter.Gte(o => o.Total, 100);
var list = await col.Find(f).Sort(Builders<Order>.Sort.Descending(o => o.CreatedAt)).Limit(50).ToListAsync(ct);
var u = Builders<Order>.Update.Set(o => o.Status, "Paid").CurrentDate(o => o.UpdatedAt);
var res = await col.UpdateOneAsync(o => o.Id == order.Id, u, cancellationToken: ct);   // res.MatchedCount / ModifiedCount
```
- **Sempre use os métodos `*Async` com `CancellationToken`** em ASP.NET Core (`csharp-async-await`); a doc mostra versões síncronas nos exemplos.
- Sem critério de ordenação, `FirstOrDefault()` devolve o primeiro documento em **ordem natural** em disco (doc); se a regra depende de ordem, informe `Sort` (CONVENÇÃO). Filtro vazio: `Builders<T>.Filter.Empty`.
- **Cursores**: `ToList()` carrega tudo — a doc avisa que resultado maior que a memória derruba o processo; itere o cursor (`ToCursorAsync`/`ForEachAsync`) e **crie cursor com `using`** (Dispose).
- **Projeção**: com `Expression()`/lambda o `_id` só vem se incluído; com projeção por builder o `_id` vem a não ser que excluído. Projete só o necessário (CONVENÇÃO).
- **Update**: `UpdateOne`/`UpdateMany` (+ operações em arrays com operadores posicionais e `arrayFilters` — páginas existem; não li em detalhe). **Replace**: `_id` é imutável; se o documento de substituição trouxer `_id` ele deve ser igual ao existente (use `[BsonIgnoreIfDefault]` no `_id` do POCO se estiver vazio).
- **Bulk** (`BulkWriteAsync` com `InsertOneModel`, `UpdateOneModel`, `DeleteOneModel`…): usa o write concern da coleção; erros de write concern só são reportados **depois de tentar todas** as operações; `InsertOneModel` com `_id` existente → `MongoBulkWriteException`. Reduz round-trips (CONVENÇÃO: prefira a N chamadas isoladas).
- **Write concern/read concern** configuráveis em cliente/banco/coleção (`WithWriteConcern(WriteConcern.WMajority)` retorna nova instância).
- **Repository genérico sobre `IMongoCollection`**: geralmente só duplica a API; prefira repositórios por agregado/caso de uso (CONVENÇÃO).

## LINQ [MDB]
`collection.AsQueryable()` → LINQ traduzido para **aggregation pipeline**. Desde o **v3 só existe o provider LINQ3** (LINQ2 removido; `IMongoQueryable` → `IQueryable`). Projeções **no cliente** lançam `ExpressionNotSupportedException` por padrão; habilite com `TranslationOptions.EnableClientSideProjections = true` (por consulta via `FindOptions`/`AggregateOptions` ou globalmente em `MongoClientSettings`) — **só se entender o custo** (traz documentos inteiros). Nem todo operador LINQ é traduzível; teste contra Mongo real. Pipelines manuais com `BsonDocument` não aplicam atributos/convenções.

## Índices [MDB]
- Sem índice o servidor faz **collection scan** em toda consulta. `Builders<T>.IndexKeys` → `CreateIndexModel<T>` → `collection.Indexes.CreateOne(...)` (forma mostrada na doc; a variante assíncrona **não aparece na doc que li**).
- Indexe campos de filtro/ordenação frequentes; índices consomem disco/memória e atualizam a cada escrita; *covered queries* quando query/projeção/sort estão no mesmo índice; wildcard index **não** substitui planejamento. Crie índices **na inicialização controlada/migração**, não a cada request (CONVENÇÃO). Índice único protege duplicidade que validação em código não evita (corrida).
- O provider EF **não suporta migrations** [MDB-EF]; a doc do driver que li não descreve migração de esquema — evolução de esquema (campos novos/renomeados) é por código tolerante (`[BsonIgnoreExtraElements]`, valores default) ou migração de dados própria (CONVENÇÃO).

## Transações e sessões [MDB]
- Sessão: `client.StartSession()` / `StartSessionAsync()`. **Use a sessão só com o cliente que a criou** (outro cliente → erro) e passe-a como **primeiro argumento** de cada operação (a doc mostra `books.InsertOne(session, book)`; o exemplo é síncrono).
- `StartTransaction`/`CommitTransactionAsync`/`AbortTransactionAsync` ou **`WithTransaction(Async)`** (inicia a transação e executa o callback `Func<IClientSessionHandle, CancellationToken, Task<TResult>>`; a doc remete ao manual do servidor para detalhes — **não li** sobre retry automático). **Importante (doc):** se capturar exceção dentro do callback de `WithTransaction(Async)`, **relance-a** antes de sair do try/catch — senão pode haver **loop infinito**.
- `ClientSessionOptions`: `CausalConsistency` (padrão `true`), `DefaultTransactionOptions`, `Snapshot` (padrão `false`).
- Requisitos de servidor para transações (replica set/sharded cluster) e limites estão no **manual do servidor — não li**. CONVENÇÃO: modele agregados para que a maioria das operações seja **atômica em um único documento**, e use transação só quando necessário.

## Change streams [MDB]
`Watch()`/`WatchAsync()` em coleção, banco ou cliente; `pipeline` com `EmptyPipelineDefinition` para filtrar eventos. Pré/pós-imagens só com **MongoDB ≥ 6.0**; eventos grandes podem vir fragmentados (`$changeStreamSplitLargeEvent`; reagrupar é recomendado). Uso típico: `BackgroundService` (`aspnet-hosted-services`) — trate **retomada** (resume token) e reconexão (CONVENÇÃO; detalhes de resume não li).

## Logging e monitoramento [MDB]
- Logging do driver: requer o pacote `Microsoft.Extensions.Logging.Console` no exemplo da doc; `settings.LoggingSettings = new LoggingSettings(loggerFactory)`. Categorias: `MongoDB.Command`, `MongoDB.SDAM` (topologia), `MongoDB.ServerSelection`, `MongoDB.Connection`, `MongoDB.Internal.*`; nível por categoria (`LogLevel:<categoria>`). Mensagens como `CommandStarted` **truncam o campo `Command`** em um número configurável de caracteres (padrão **1000**) — ainda assim trate logs de comando como potencialmente sensíveis (CONVENÇÃO). Eventos programáticos: `ClusterConfigurator` + `Subscribe<TEvent>()` (monitoring). Métricas/traces: `dotnet-observability`.

## Provider EF Core para MongoDB [MDB-EF]
- Alternativa quando o time quer modelagem/`DbContext` do EF: `MongoDB.EntityFrameworkCore` (builds sobre o driver; change tracking, LINQ de entidades, fluent API, `HasIndex`). **Limitações da doc lida:** sem **migrations**, database-first, foreign/alternate keys, table splitting, temporal tables, spatial, time series, Atlas Search/Vector Search; **Select projections** constavam como não suportadas (a doc pode estar desatualizada — confira). A doc avisa que o provider **não restringe breaking changes a majors** (podem vir em minors) — fixe a versão. Recursos do driver continuam acessíveis pelo `MongoClient` usado no `DbContext`.
- Driver direto = mais controle (bulk, transações explícitas, aggregation, mapeamento flexível); EF provider = ergonomia EF. Decida por caso (CONVENÇÃO).

## Upgrade para o driver v3 [MDB]
Breaking changes: removido suporte a MongoDB ≤ 3.6 (v3.0) e **≤ 4.0 (a partir de 3.5; exige servidor ≥ 4.2)**; .NET Core 2.x e .NET Framework 4.6 não suportados; pacote `mongocsharpdriver` (API v1) removido; `MongoDB.Driver.Core` obsoleto → `internal`; `MONGODB-CR` removido; LINQ2 removido; `IMongoQueryable` → `IQueryable`; `ClusterBuilder.ConfigureSdamLogging()` removido (use `LoggingSettings`); GUID só modo V3; exceções sem `[Serializable]`. Migre 2.x → última 2.x (corrigindo avisos de obsolescência) → 3.x.

## Testes (CONVENÇÃO)
Prefira Mongo **real** em container (Testcontainers — `dotnet-local-dev-containers`, `dotnet-integration-testing`) a mocks de `IMongoCollection` (LINQ/serialização/índices só se validam no servidor). Limpe dados por teste/coleção e crie os índices no setup.

## Checklist de revisão
- [ ] **Um** `MongoClient` singleton (DI); nada de `new MongoClient` por request; pool/timeouts conhecidos.
- [ ] Connection string/credenciais fora do código; TLS ativo; `AllowInsecureTls` não usado em produção; usuário com menor privilégio.
- [ ] Filtros por Builders/LINQ/parâmetros tipados, sem concatenar entrada do usuário em JSON/`BsonDocument`.
- [ ] POCO: `_id` bem definido (`ObjectId` ou `[BsonId]`+representação), `[BsonIgnoreExtraElements]` onde o esquema evolui, convenção camelCase registrada uma vez, tipos casando com o banco.
- [ ] GUID em `Standard`/subtype 4 (ou `ObjectId`); `DateTime` em UTC (ou `DateOnly` consciente).
- [ ] Métodos `Async` + `CancellationToken`; cursores com `using`/iteração; nada de `ToList()` sobre resultado ilimitado.
- [ ] Índices criados para os filtros/ordenações reais; unicidade garantida por índice único.
- [ ] Transações só onde necessário; callbacks de `WithTransaction` **relançam** exceções; sessão usada com o mesmo cliente.
- [ ] LINQ: sem depender de projeção no cliente sem `EnableClientSideProjections` consciente; consultas testadas contra Mongo real.
- [ ] Change streams: retomada/reconexão tratadas; roda em hosted service.
- [ ] Logging por categoria configurado sem vazar dados; versão do driver compatível com a do servidor e do .NET (tabela de compatibilidade).
- [ ] Se EF provider: limitações aceitas (sem migrations/FKs), versão fixada.

## Fontes [MDB]
- https://www.mongodb.com/docs/drivers/csharp/current/ (repo `mongodb/docs-csharp`): connect/mongoclient, connect/connection-options (+connection-pools, server-selection, stable-api), connection-troubleshooting, serialization/poco, class-mapping, guids, crud (insert, query/find, cursors, project, replace, bulk-write, configure, transactions), aggregation/linq e stages, indexes, logging-and-monitoring (logging, monitoring, change-streams), security (tls-ssl, authentication/scram), reference (compatibility, upgrade/v3), restful-api-tutorial.
- https://www.mongodb.com/docs/entity-framework/current/ (repo `mongodb/docs-entity-framework`): faq, limitations, whats-new.
