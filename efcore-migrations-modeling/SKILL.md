---
name: efcore-migrations-modeling
description: Configurar o modelo e as migrations do EF Core - entidades, chaves, Fluent API vs Data Annotations, IEntityTypeConfiguration, ApplyConfigurationsFromAssembly, dotnet ef migrations add, database update, bundles, scripts SQL, aplicar migrations em produção. Use quando o usuário pedir para mapear entidades, criar/aplicar migration ou revisar OnModelCreating. Based on official Microsoft Learn docs.
---

# EF Core — modelagem e migrations

Só afirmar o que a doc oficial diz (fontes no fim). Relacionamentos, tipos de propriedade, índices e valores gerados: consultar as páginas de *Modeling* antes de detalhar (não cobertas aqui).

## Modelo
- O EF monta um modelo por **convenções**; você personaliza com **Data Annotations** (atributos) e/ou **Fluent API** em `OnModelCreating`.
- **Precedência:** Fluent API > Data Annotations > convenções. Em conflito entre chamadas, a última vence.
- Fluent API não suja a entidade com atributos de infraestrutura e é a mais poderosa.

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<Blog>().Property(b => b.Url).IsRequired();
}
```

### Agrupar configuração
```csharp
public class BlogEntityTypeConfiguration : IEntityTypeConfiguration<Blog>
{
    public void Configure(EntityTypeBuilder<Blog> builder) =>
        builder.Property(b => b.Url).IsRequired();
}
// em OnModelCreating:
modelBuilder.ApplyConfigurationsFromAssembly(typeof(BlogEntityTypeConfiguration).Assembly);
```
- `ApplyConfigurationsFromAssembly`: ordem **indefinida** (só use se a ordem não importa) e só instancia classes com construtor sem parâmetros (as outras geram aviso e são puladas).
- Alternativa: `[EntityTypeConfiguration(typeof(X))]` na entidade (a entidade precisa estar no modelo).
- Bulk configuration/conventions: `ConfigureConventions`.
- Debug: `context.Model.ToDebugString()`.
- Entidades: **classes** com chave; **não usar `record`** como entidade (EF depende de igualdade por referência). Ver `dotnet-model-review`.

## Migrations
Fluxo (doc):
```bash
dotnet ef migrations add InitialCreate        # gera arquivos em Migrations/ + snapshot do modelo
dotnet ef database update                     # aplica ao banco (ideal para desenvolvimento local)
dotnet ef migrations add AddBlogCreatedTimestamp   # nome descritivo
```
- EF compara o modelo atual com o **snapshot** e gera a migration; arquivos vão no controle de versão. O banco guarda a **tabela de histórico** de migrations aplicadas.
- Nomeie com descrição clara (`AddBlogCreatedTimestamp`).
- **Produção:** `database update` direto é para dev. Doc recomenda: **migration bundle** para automação de deploy; **script SQL revisado** quando for preciso aprovar/modificar SQL; projetos específicos de plataforma → migrations em **projeto separado com design-time factory**. (Detalhes na página *Applying migrations*; confirmar antes de recomendar `Migrate()` no startup.)
- Tipos de outro DbContext no modelo → conflito: `ToTable(..., t => t.ExcludeFromMigrations())`.
- Instale as ferramentas `dotnet ef` (ou Package Manager Console no Visual Studio).
- Revise sempre o código gerado (pode ser alterado).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Configuração do modelo em Fluent API/`IEntityTypeConfiguration`, não espalhada |
| 2 | Required/optional coerentes com nullability do C# (ver `csharp-nullable-references`) |
| 3 | Chaves e relacionamentos explícitos quando a convenção não basta |
| 4 | Migrations versionadas no Git, com snapshot, nomes descritivos |
| 5 | Migration revisada (colunas perdidas, drops de dados) |
| 6 | Estratégia de produção definida (bundle/script), não `database update` na máquina do dev |
| 7 | Entidade não é `record` |
| 8 | Índices em colunas filtradas com frequência (e FK) conscientes (convenção cria índice para FK) |
| 9 | Projeto de migrations separado quando a plataforma exige |

## Fontes oficiais
- Modeling: https://learn.microsoft.com/en-us/ef/core/modeling/
- Migrations overview: https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/
- Applying migrations: https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying
- Managing migrations: https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/managing
- Ferramentas CLI: https://learn.microsoft.com/en-us/ef/core/cli/dotnet
