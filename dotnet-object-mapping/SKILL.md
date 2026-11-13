---
name: dotnet-object-mapping
description: Decidir e revisar como mapear entre entidades, DTOs e view models em .NET - mapeamento manual (construtores, métodos de extensão, projeção com Select do EF Core, with/records) versus bibliotecas (Mapperly source generator, Mapster, AutoMapper), projeção IQueryable, overposting, validação de configuração, mapeamento em coleções e aninhados. Use quando o usuário perguntar "AutoMapper ou manual?", for escrever mapeamentos Entity↔DTO, ou revisar mappers. ⚠ Não existe guia oficial da Microsoft sobre bibliotecas de mapeamento; esta skill separa o que é oficial do que vem da documentação das bibliotecas (terceiros).
---

# Mapeamento de objetos (Entity ↔ DTO ↔ ViewModel)

**Proveniência:**
- **Oficial Microsoft:** *por que* separar entidade de DTO/view model (overposting, só os campos necessários), projeção com `Select` no EF Core, `record`/`with`. A doc **menciona** AutoMapper apenas como exemplo opcional ("optionally by using a tool such as AutoMapper"). **A Microsoft não recomenda nem documenta uma biblioteca de mapeamento.**
- **[LIB] Terceiros:** README/docs de Mapperly, Mapster e AutoMapper (lidos nos repositórios oficiais das bibliotecas).
Ligações: `dotnet-dto-review` (o que um DTO deve ter), `dotnet-model-review`, `efcore-querying` (projeção/tracking), `aspnet-validation`, `csharp-modern-features`.

## Por que mapear (oficial)
- Evitar **overposting**: a doc de EF/MVC prefere **view models em vez de entidades no model binding**; inclua só as propriedades que podem ser alteradas e depois **copie o view model para a entidade** (opcionalmente com uma ferramenta como AutoMapper) — ver `dotnet-dto-review`.
- **Leitura eficiente:** use **`Select`** para o EF buscar só as colunas necessárias (a doc mostra o SQL reduzido de `SELECT [b].[Url]` vs. todas as colunas) ⇒ projetar direto para o DTO na query é o caminho oficial; sem tracking de entidades inteiras (ver `efcore-querying`).
- Em CQRS, o lado de **consulta** pode usar ORM completo, *projeções* (a doc cita AutoMapper), SPs, views ou micro-ORM — ou seja, mapeamento por projeção é aceito.

## Opções de implementação
| Opção | Quando | Observações |
|---|---|---|
| **Manual** (método/extension `ToDto()`, construtor de record, `Select(x => new Dto(...))`) | Padrão seguro; poucos tipos; regras de negócio no mapeamento | Explícito, depurável, sem dependência; **trabalho repetitivo** e fácil esquecer um campo ao evoluir o modelo. Compilador ajuda se o DTO usa `required`/construtor posicional (campo novo obrigatório quebra a build). |
| **Mapperly [LIB]** | Muito mapeamento "propriedade a propriedade", quer desempenho/inspeção | **Source generator**: o código é gerado **em tempo de build**, "overhead mínimo em runtime" e **legível/verificável**. Declare `[Mapper] public partial class CarMapper { public partial CarDto CarToCarDto(Car car); }`. Suporta **`IQueryable<T>` projections** (`public static partial IQueryable<CarDto> ProjectToDto(this IQueryable<Car> q)`; só os campos do alvo vêm do banco) com **limitações** (sem object factories, sem reference handling, nullable reference types desabilitado, enum `ByName` não suportado etc.); guardas de null viram `CASE WHEN` no SQL e podem afetar uso de índices — leia a doc de null handling. Canal *Next* é preview (pode quebrar). |
| **Mapster [LIB]** | Mapeamento por configuração/convenção com runtime ou geração (`Mapster.Tool`) | Pacotes extras (EFCore, DependencyInjection, Immutable...). Verifique a doc da biblioteca para a versão que usar. |
| **AutoMapper [LIB]** | Projeto legado que já usa | Configuração `CreateMap<A,B>()` + `AddAutoMapper(...)`; README recomenda **`AssertConfigurationIsValid()` só em desenvolvimento**. **O README atual do repositório (Lucky Penny Software) exige `LicenseKey` obtida em automapper.io**: confira os **termos de licença** antes de adotar/atualizar. Mapeamento por reflexão/convenção em runtime (erros aparecem tarde se não validar). |
- **Recomendação (CONVENÇÃO, não oficial):** comece **manual** (ou Mapperly se houver muito boilerplate), prefira geração em build-time a reflexão, e **sempre projete com `Select`/ProjectTo na query** em vez de carregar a entidade inteira para mapear em memória. Evite colocar regra de negócio ou acesso a banco dentro de mapeamentos mágicos.

## Regras práticas de revisão
- **Direção e escopo:** Entity→DTO (saída) e Request→Entity/Command (entrada) são mapeamentos diferentes; **nunca** devolver a entidade EF direto ao cliente nem bindar entidade em endpoint (ver `dotnet-dto-review`).
- **Atualização:** para PUT/PATCH, mapear **sobre a entidade carregada** (rastreada) e deixar o EF detectar mudanças; não criar nova entidade com mesmo Id sem querer (ver `efcore-saving-concurrency`).
- **Coleções e aninhados:** mapeie coleções com `Select` e evite `Include` desnecessário quando só o DTO precisa de alguns campos (projeção resolve o join). Cuidado com **ciclos** (navegações bidirecionais) e com **N+1** quando o mapper acessa navegações em memória (lazy loading — `efcore-relationships-loading`).
- **Null/nullable:** alinhe com `csharp-nullable-references`; mapper não deve mascarar `null` inesperado.
- **`record` + `with`:** para cópias imutáveis com alteração, use `with` (ver `csharp-types-oop`); `with` faz cópia rasa.
- **Teste:** cubra mapeamentos críticos com testes unitários (`dotnet-unit-testing`); com bibliotecas de config, rode validação de configuração (ex.: `AssertConfigurationIsValid` do AutoMapper) em teste/CI.
- **Desempenho:** mapeamento em memória de N itens é barato frente a I/O; o ganho grande vem de **não buscar colunas/tabelas desnecessárias** (projeção).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Entidade EF exposta na API ou usada como alvo de binding (overposting) | Alta |
| 2 | Carregar entidade completa + mapear em memória quando `Select`/ProjectTo bastaria | Média |
| 3 | Mapper com lógica de negócio/IO/acesso ao `DbContext` | Média |
| 4 | Biblioteca de mapeamento sem validação de configuração (campo esquecido só falha em runtime) | Média |
| 5 | Dependência com licença/termos não verificados (AutoMapper atual) | Média |
| 6 | Mapper que acessa navegações não carregadas (N+1/lazy loading) | Alta |
| 7 | Mapeamento Request→Entity sobrescrevendo campos que o cliente não pode alterar | Alta |
| 8 | Projeções IQueryable com recursos não suportados pela biblioteca (ver limitações) | Média |
| 9 | Mapeamento duplicado/inconsistente entre camadas sem dono claro | Baixa |

## Fontes
- **Oficial** — ASP.NET Core + EF (view models vs overposting): https://learn.microsoft.com/en-us/aspnet/core/data/ef-mvc/crud
- **Oficial** — EF Core efficient querying (`Select`/projeção): https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying
- **Oficial** — CQRS/consultas em microsserviços (menciona projeções): https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/eshoponcontainers-cqrs-ddd-microservice
- **Oficial** — `with` expression: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/with-expression
- **[LIB]** Mapperly: https://github.com/riok/mapperly · docs https://mapperly.riok.app
- **[LIB]** Mapster: https://github.com/MapsterMapper/Mapster
- **[LIB]** AutoMapper: https://github.com/LuckyPennySoftware/AutoMapper · licença: https://automapper.io
