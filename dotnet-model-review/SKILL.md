---
name: dotnet-model-review
description: Implementar e revisar models/entidades em C# (classes de domínio, entidades EF Core, propriedades, required, init, nullable, record vs class, record struct, igualdade, imutabilidade, construtores, propriedades calculadas, separação model/entity vs DTO). Use quando o usuário pedir para criar um model ou entidade, verificar se está correto ou decidir entre class, record e struct. Based on official Microsoft Learn docs.
---

# Models / Entidades em C# — implementar e revisar

Só afirmar o que a doc oficial diz (fontes no fim). DTOs: `dotnet-dto-review`. Mapeamento EF: `efcore-migrations-modeling`. Nullability: `csharp-nullable-references`.

## Escolher: class, record, struct

| Tipo | Igualdade | Imutabilidade | Quando (segundo a doc) |
|---|---|---|---|
| `class` | por **referência** | mutável por padrão | **Entidades do EF Core** (depende de referência para ter uma instância por entidade) |
| `record` / `record class` | por **valor** (mesmo tipo + mesmos valores) | `init` nas posicionais | Modelos de dados imutáveis (a doc diz "primariamente destinados" a isso; usar para DTOs/value objects/mensagens é CONVENÇÃO) |
| `readonly record struct` | por valor | imutável | Value-type com semântica de valor (o "pequeno" vem da doc de struct: ~16 bytes) |
| `record struct` | por valor | propriedades posicionais **mutáveis** | Idem, mas mutável |
| `struct` | por valor | — | Decida como class vs struct |

- Records são feitos para **modelos imutáveis**, mas podem ser mutáveis (`{ get; set; }`).
- **Records NÃO são apropriados como entidades do EF Core**: EF depende de igualdade por referência e não suporta atualização de tipos imutáveis.
- Record posicional gera: propriedades públicas `init`, construtor primário, `Deconstruct`, `ToString`, igualdade, `with`. Pode redefinir a propriedade gerada (acessibilidade/validação) inicializando-a pelo parâmetro.
- `with` faz **cópia rasa** (referências compartilhadas). Propriedade calculada deve ser calculada no **acesso**.
- Herança: record herda só de record; igualdade compara o tipo em runtime (`EqualityContract`).

## Propriedades obrigatórias
- `required` (C# 11) em campos/propriedades de class/struct/record: o object initializer precisa defini-los. Regras: acessibilidade ≥ tipo contido; precisa de setter `set`/`init`; não pode esconder `required` da base; incompatível com `new()` genérico; não vale em parâmetro posicional de record; `[SetsRequiredMembers]` desliga a checagem (usar com cuidado).
- Alternativa: parâmetros no construtor primário.

```csharp
public class Todo                      // entidade EF = class
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public bool IsComplete { get; set; }
    public string? Secret { get; set; }   // opcional = nullable
}
```
### Construtores em entidades EF Core (doc "Entity types with constructors")
- Por padrão o EF cria a instância chamando o **construtor sem parâmetros** e depois define cada propriedade.
- Se achar um construtor **parametrizado** cujos nomes/tipos de parâmetros casem com propriedades mapeadas (por convenção), ele o usa, passando os valores lidos do banco; propriedades sem parâmetro correspondente são definidas depois.
- O construtor pode ser `public`, `private` ou outro; **proxies de lazy loading** exigem acessível pela classe proxy (public/protected).
- O EF **não** define propriedades de **navegação** pelo construtor.
- Dá para tornar propriedades somente leitura (set no construtor), mas **propriedades sem setter não são mapeadas por convenção**; a doc sugere setter `private` (o EF o trata como leitura/escrita) ou mapeamento explícito no `OnModelCreating`. Chave gerada pelo banco não precisa estar no construtor.
- Todo binding de construtor é **por convenção** (configuração de qual construtor usar ainda não existe).
- A página consultada não menciona o modificador `required`; se o usuário combinar `required` com EF, valide na doc/teste antes de garantir.

## Boas práticas verificadas
1. Habilite nullable e deixe claro obrigatório (`string`) x opcional (`string?`).
2. Não exponha a entidade na API: use DTO.
3. Coleções de navegação: inicialize (`= []`) e não exponha setter público desnecessário (diretriz de coleções: sem setter; nunca `null`).
4. Evite lógica de apresentação no model; propriedades calculadas simples via `=>`.
5. Sealed quando não herdada (EF DbContext doc recomenda `sealed` para o contexto; para entidades com lazy loading proxies, classes precisam ser herdáveis: conferir doc de lazy loading).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Entidade EF é `class` (não `record`/`struct`) |
| 2 | Chave definida/convencional (`Id` ou `ClassNameId`) |
| 3 | Nullability coerente com colunas obrigatórias/opcionais |
| 4 | Sem `null!`/`= default!` espalhado sem motivo |
| 5 | Coleções inicializadas, sem setter público quando possível |
| 6 | Model não é usado como contrato HTTP |
| 7 | Propriedade calculada em record não congelada no construtor |
| 8 | `required` usado com consciência das regras acima |
| 9 | Value objects imutáveis (record) separados de entidades |
| 10 | Campos sensíveis (`Secret`, senha) nunca mapeados para saída |

## Fontes oficiais
- Records: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/record
- `required`: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/required
- Nullable references: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/null-safety/nullable-reference-types
- EF Core modeling: https://learn.microsoft.com/en-us/ef/core/modeling/
- Entity types with constructors (EF): https://learn.microsoft.com/en-us/ef/core/modeling/constructors
