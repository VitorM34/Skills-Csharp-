---
name: efcore-relationships-loading
description: Modelar e revisar relacionamentos e carregamento de dados relacionados no EF Core - one-to-many, one-to-one, many-to-many, chaves estrangeiras/principais, navegações, required vs optional, cascade delete, eager loading (Include/ThenInclude/filtered include), explicit e lazy loading, split queries, global query filters (soft delete, multi-tenancy). Use quando o usuário pedir para mapear relações entre entidades, resolver carregamento de navegações ou N+1, configurar soft delete ou revisar cascade. Based on official Microsoft Learn docs (EF Core).
---

# EF Core — relacionamentos, carregamento e filtros globais

Só afirmar o que a doc oficial diz (fontes no fim). Consultas eficientes em geral: `efcore-querying`. Modelagem base: `efcore-migrations-modeling`. Mapeamento avançado: `efcore-advanced-mapping`.

## Conceitos
- Relacionamento (modelo relacional): **chave primária** no principal, **chave estrangeira** no dependente, restringida a valores existentes. No EF: **principal (pai)** e **dependente (filho)**; navegações opcionais: *collection navigation* (no principal) e *reference navigation* (no dependente). Relação com as duas navegações = **bidirecional**.
- **Required × optional:** FK **não nullable** ⇒ relação **required** (todo dependente tem principal). *Required não garante que o principal tenha dependentes*: não há como impor isso no modelo EF nem no relacional. Propriedades de chave não precisam ser públicas, mas **existem** no modelo.
- **Fonte da verdade da configuração:** a **API de construção do modelo (Fluent API)** tem precedência sobre convenções e atributos de mapeamento e é a única com fidelidade total.
- **Descoberta por convenção** (ver "Relationship conventions"): ex. `Blog.Id` + `Post.BlogId` + `Post.Blog` → `Blog` principal, `Post` dependente, `Post.BlogId` FK.

```csharp
public class Blog { public int Id { get; set; } public ICollection<Post> Posts { get; } = new List<Post>(); }
public class Post { public int Id { get; set; } public int BlogId { get; set; } public Blog Blog { get; set; } = null!; }
```

## Tipos de relação
- **One-to-many**: principal com coleção + dependente com FK (e navegação de referência opcional).
- **One-to-one**: **a tabela com a coluna de FK mapeia o tipo dependente**; dependente = tipo que não existe logicamente sem o outro / filho natural. Em required one-to-one o dependente exige o principal.
- **Many-to-many**: não cabe numa FK; precisa de **join entity/tabela**. O EF pode **esconder a entidade de junção** e expor navegações diretas (`Post.Tags` ↔ `Tag.Posts`); mapeie a entidade explicitamente (payload na junção) quando precisar de colunas extras.
- **Chaves alternativas**: introduzidas quando uma propriedade que não é PK é alvo de relacionamento; se só quer unicidade, prefira **índice único**.

## Cascade delete (doc)
- Relações **required** usam **cascade delete por padrão**. Há dois jeitos de evitar violação de constraint ao remover o principal: apagar/ re-relacionar dependentes, ou FK nullable (só relações **opcionais**).
- **Severing** (anular navegação) e **órfãos** são casos de remoção por quebra de relação.
- O EF **sempre aplica** cascata nas entidades **rastreadas** (se você carregou os dependentes no contexto, a cascata acontece independentemente do banco). Sem `Include`, só o principal é rastreado e a cascata depende do **banco**. O banco não apaga órfãos automaticamente (só tem FKs, não navegações).
- ⚠ **Não configure cascade delete no banco ao usar soft delete** (pode apagar de verdade por engano). Há limitações de cascata em bancos (ciclos).

## Carregando dados relacionados
| Estratégia | Como | Notas (doc) |
|---|---|---|
| **Eager** | `Include`, `ThenInclude`, múltiplos níveis, **filtered include** (`Where/OrderBy/Take` dentro do `Include` da coleção) | um roundtrip; cada navegação de coleção aceita **um** conjunto de filtros; com queries *tracking*, **fixup de navegação** pode trazer entidades já rastreadas que não atendem ao filtro (use `NoTracking` ou recrie o contexto); `Include` em tipos derivados; `AutoInclude` no modelo e `IgnoreAutoIncludes()` na query |
| **Explicit** | `context.Entry(x).Collection(...).Load()` / `.Query()` | roundtrip extra; útil se a necessidade depende de outro dado |
| **Lazy** | proxies (`UseLazyLoadingProxies`: navegações `virtual` em classe herdável) ou `ILazyLoader` (parâmetro do construtor chamado `lazyLoader`) | ⚠ **N+1**: evitar (ver `efcore-querying`) |
- O EF **corrige (fixup) automaticamente navegações** para entidades já carregadas no contexto.
- **Single vs split queries:** um `Include` de coleção gera **JOIN** → **cartesian explosion** (várias coleções multiplicam linhas) e duplicação de dados (relevante com colunas grandes no principal). **Split query** (`AsSplitQuery()`, ou global) gera uma query por coleção incluída. Padrão do EF: **single** (gera warning quando detecta o risco). Navegações **one-to-one** sempre vêm por JOIN. Com `Skip/Take` e split query em versões **anteriores ao EF 10**, garanta **ordenação totalmente única** (data + ID) para não retornar dados incorretos.
- Projetar só o necessário (`Select`) evita colunas grandes, mas o resultado (tipo anônimo) **não é rastreado**.
- Serialização de grafos com ciclos: ver "Related data and serialization" (prefira DTOs; `dotnet-dto-review`).

## Global query filters (doc "Global Query Filters")
- Filtro aplicado **a todas as consultas** de um tipo; usos: **soft delete** (`HasQueryFilter(b => !b.IsDeleted)`; para persistir como soft delete sobrescreva `SaveChanges(Async)` convertendo `Deleted` em `Modified` com `IsDeleted = true`) e **multi-tenancy** (o `tenantId` precisa estar na instância do contexto, injetado no construtor; tenha cuidado com **DbContext pooling**: o contexto é reutilizado entre requisições, então o estado do tenant precisa ser tratado). Para ignorar: `IgnoreQueryFilters()`. Origem do tenant ID é **aspecto de segurança**.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Loop acessando navegação (lazy/N+1) | Alta |
| 2 | Vários `Include` de coleção sem split em tabelas grandes | Média |
| 3 | FK/navegação required vs optional não reflete a regra de negócio (nullable) | Média |
| 4 | Cascade delete inesperado (required por padrão) ou combinado com soft delete | Alta |
| 5 | Filtered include com tracking (resultado inesperado por fixup) | Média |
| 6 | Many-to-many com payload mapeado como "esconde junção" | Média |
| 7 | One-to-one com lado principal/dependente invertido em relação ao banco | Média |
| 8 | Entidades com ciclo serializadas direto na API | Alta |
| 9 | Filtro global esquecido em `IgnoreQueryFilters` ou tenant ID de fonte não confiável | Alta |
| 10 | Split query com `Skip/Take` sem ordenação única (EF < 10) | Média |

## Fontes oficiais
- Relationships (introdução): https://learn.microsoft.com/en-us/ef/core/modeling/relationships
- One-to-many: https://learn.microsoft.com/en-us/ef/core/modeling/relationships/one-to-many
- One-to-one: https://learn.microsoft.com/en-us/ef/core/modeling/relationships/one-to-one
- Many-to-many: https://learn.microsoft.com/en-us/ef/core/modeling/relationships/many-to-many
- Cascade delete: https://learn.microsoft.com/en-us/ef/core/saving/cascade-delete
- Eager loading: https://learn.microsoft.com/en-us/ef/core/querying/related-data/eager
- Explicit loading: https://learn.microsoft.com/en-us/ef/core/querying/related-data/explicit
- Lazy loading: https://learn.microsoft.com/en-us/ef/core/querying/related-data/lazy
- Single vs split queries: https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries
- Global query filters: https://learn.microsoft.com/en-us/ef/core/querying/filters
