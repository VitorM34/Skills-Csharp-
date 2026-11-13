---
name: efcore-advanced-mapping
description: Mapeamento avançado no EF Core - chaves (compostas, alternativas, tipos de chave), propriedades (colunas, tipos, tamanho máximo, precisão, Unicode, required), valores gerados (default, computed, timestamps), índices, owned entity types vs complex types (value objects), herança TPH, value converters, keyless entities, shadow/indexer properties, data seeding (UseSeeding). Use quando o usuário pedir para mapear value objects, converter tipos, configurar índices/valores gerados, herança ou popular dados iniciais. Based on official Microsoft Learn docs (EF Core 10).
---

# EF Core — mapeamento avançado

Só afirmar o que a doc oficial diz (fontes no fim). Base de modelagem/migrations: `efcore-migrations-modeling`. Relacionamentos: `efcore-relationships-loading`. Entidades C#: `dotnet-model-review`.

## Chaves
- Configure PK por convenção (`Id`/`TypeId`), Data Annotation `[Key]` ou Fluent `HasKey`. **Chave composta**: só por Fluent (a convenção só cria em casos específicos, como coleção de owned type). Qualquer tipo primitivo (`string`, `Guid`, `byte[]`…) pode ser chave, mas **nem todo banco suporta todos os tipos**; conversão automática ou manual (`value conversions`).
- Chave deve ter valor **não padrão** ao adicionar, exceto quando **gerada pelo banco** (o EF usa um valor **temporário** até o `SaveChanges`). ⚠ **Se a chave é gerada pelo banco e você informa um valor não padrão ao adicionar, o EF assume que a entidade já existe e tenta atualizar** (não inserir); para inserir com valor explícito, desligue a geração ou veja "overriding value generation".
- **Chaves alternativas**: só leitura e podem ser alvo de FK; **para apenas unicidade use índice único**.

## Propriedades
- Colunas: nome, tipo, **`HasMaxLength`** (dica ao provedor sobre o tipo; só em `string`/`byte[]`), **precisão e escala** (`HasPrecision(p, s)`/`[Precision]`; escala nunca sem precisão), **Unicode** (texto é Unicode por padrão; configurável para `varchar` onde existir).
- **Required × optional:** por convenção, tipo que aceita `null` ⇒ opcional (coluna nullable); tipos que não aceitam ⇒ required. Com nullable reference types habilitado, `string` = required, `string?` = optional (ver `csharp-nullable-references`).
- Propriedades incluídas/excluídas, backing fields, **indexer/shadow properties** (existem só no modelo; **não acessíveis após query no-tracking**).

## Valores gerados
- **Default values** (valor ou fragmento SQL; também preenchem linhas existentes ao adicionar coluna), **computed columns** (SQL), **chaves** (auto-incremento etc.), geração explícita (`ValueGeneratedOnAdd/OnAddOrUpdate/Never`: o **como** depende do provedor).
- **Datas:** providers geralmente **não** configuram geração automática de data/hora; para **criação** use default com a função SQL (ex.: `GETUTCDATE()` no SQL Server); para **atualização** computed columns costumam ser inviáveis (funções não determinísticas): use **interceptors/eventos do `SaveChanges`** ou triggers. EF 10: nomes explícitos para default constraints no SQL Server (`UseNamedDefaultConstraints`; **renomeia todas na próxima migration**).

## Índices
Convenção cria índice para **FK**; `HasIndex`/`[Index]`. **Composto** acelera filtros por todas as colunas **e pelas primeiras** colunas; **único** (`IsUnique`); **ordem** por coluna (importante em compostos); **nome** (`HasDatabaseName`); **filtrado** (`HasFilter`; reduz tamanho/ custo em bancos que suportam); **colunas incluídas**. Segunda chamada `HasIndex` sobre as mesmas colunas **sobrescreve** a primeira. Índices aceleram leitura e **retardam escrita**: não crie à toa (ver `efcore-querying`).

## Value objects: complex types × owned entities
| | Owned entity | **Complex type** |
|---|---|---|
| Identidade | tipo de **entidade** com chave oculta (semântica de referência) | **sem identidade**, semântica de **valor** |
| Mesma instância em 2 propriedades | **não** (ex.: endereço de cobrança = entrega falha) | **sim** |
| Tipo .NET | só referência | referência **ou valor** (struct/record) |
| Navegações para outras entidades | pode | **não** |
| `ExecuteUpdate` | **não suportado** | suportado |
- A doc **recomenda complex types para value objects** (Address, Coordinate). **Complex types não são descobertos por convenção**: `[ComplexType]` ou `ComplexProperty(...)`; em relacional são mapeados **inline na tabela da entidade** (table splitting). Não rastreados/consultados de forma independente.
- **Owned** (`OwnsOne`/`[Owned]`, não por convenção salvo Cosmos DB): parte do owner, conceito de *aggregate*; sempre dependente. Coleções owned têm chave composta por convenção.

## Herança
Por padrão **TPH** (table-per-hierarchy): uma tabela com coluna **discriminadora**; colunas dos derivados ficam **nullable**; query de derivado filtra pelo discriminador. O EF **não varre tipos base/derivados** por convenção: inclua cada tipo no modelo (`DbSet` ou `modelBuilder.Entity<T>()`); `HasBaseType` explícito. Irmãos com propriedade de mesmo nome e tipo podem **compartilhar coluna** (config). (TPT/TPC existem; consulte "Inheritance" antes de detalhar.)

## Value conversions
Convertem entre tipo do modelo e do banco (`HasConversion`, `ValueConverter<TModel,TProvider>`); `null` **nunca** é passado ao converter (null no banco = null na entidade); há **conversões predefinidas** (enum↔string, bool↔int, Guid↔string/byte[], etc.), conversores só de cast; conversão de string para número **falha se não parsear**; configuração em massa; **facets de coluna** (tamanho/precisão) e comparadores (`value comparers`) para tipos mutáveis. Ex.: enum como string no banco (`.HasConversion<string>()`).

## Keyless e outros
- **Keyless entity types** (`HasNoKey`): **nunca rastreados** (nunca inseridos/atualizados/apagados), não descobertos por convenção, não podem ser principal de relação, só navegações de referência para entidades normais, hierarquia só TPH; usos: **views sem PK**, tabelas sem PK; `ToView`/`ToTable` tratam o objeto como **view somente leitura**.
- **Constructors** (ver `dotnet-model-review`), **backing fields**, **sequences**, **table/entity splitting**, **value comparers**, **spatial**, **bulk configuration**.

## Data seeding
- **Recomendado:** `UseSeeding` e `UseAsyncSeeding` nas opções do contexto (`DbContextOptionsBuilder`). Rodam **só quando o EF faz inicialização/migração do banco** (ex.: `EnsureCreated`, `Migrate`, bundles). **Ferramentas e bundles chamam o delegate síncrono**: **sempre implemente `UseSeeding`**, mesmo que a app use async. Rodam **também após downgrade de migration**: verifique se o schema existe antes de consultar.
- Deploy automatizado que precisa do seeding: **migration bundle** ou processo de inicialização dedicado; script SQL quando o DBA precisa revisar e o seed está representado nas migrations.
- Lógica customizada (ex.: dois contextos): `SaveChangesAsync` antes da lógica principal, **fora da execução normal do app**. (Seeding via `HasData` existe; consulte a doc.)

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Value object mapeado como owned onde complex type é indicado (compartilhamento/`ExecuteUpdate`) |
| 2 | Chave gerada pelo banco recebendo valor explícito ao adicionar (vira update) |
| 3 | `string` sem `HasMaxLength` quando o banco usa tipo ilimitado; decimal sem precisão/escala |
| 4 | Índices ausentes em filtros frequentes ou índices desnecessários; índice composto na ordem errada |
| 5 | Timestamp de atualização por computed column inviável (usar interceptor) |
| 6 | Enum persistido como número sem querer / conversão sem comparer em tipo mutável |
| 7 | Herança sem registrar os tipos derivados; TPH com muitas colunas nullable sem avaliar |
| 8 | Keyless usado esperando persistência |
| 9 | Seeding só assíncrono / ausente do bundle; seeding rodando no startup da aplicação |

## Fontes oficiais
- Keys: https://learn.microsoft.com/en-us/ef/core/modeling/keys
- Entity properties: https://learn.microsoft.com/en-us/ef/core/modeling/entity-properties
- Generated values: https://learn.microsoft.com/en-us/ef/core/modeling/generated-properties
- Indexes: https://learn.microsoft.com/en-us/ef/core/modeling/indexes
- Complex types: https://learn.microsoft.com/en-us/ef/core/modeling/complex-types
- Owned entity types: https://learn.microsoft.com/en-us/ef/core/modeling/owned-entities
- Inheritance: https://learn.microsoft.com/en-us/ef/core/modeling/inheritance
- Value conversions: https://learn.microsoft.com/en-us/ef/core/modeling/value-conversions
- Keyless entity types: https://learn.microsoft.com/en-us/ef/core/modeling/keyless-entity-types
- Shadow and indexer properties: https://learn.microsoft.com/en-us/ef/core/modeling/shadow-properties
- Data seeding: https://learn.microsoft.com/en-us/ef/core/modeling/data-seeding
