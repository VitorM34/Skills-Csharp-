---
name: dotnet-xunit
description: Escrever e revisar testes com xUnit.net (Fact, Theory, InlineData, fixtures IClassFixture/ICollectionFixture, IAsyncLifetime, construtor/Dispose, collections, paralelismo, template dotnet new xunit). Use quando o projeto usa xUnit ou o usuário pedir para criar/revisar testes xUnit, compartilhar contexto entre testes ou controlar paralelismo. Based on official Microsoft Learn docs and the official xunit.net documentation.
---

# xUnit.net — escrever e revisar

Fontes: tutorial da Microsoft (xUnit com `dotnet test`) e documentação oficial do xUnit (xunit.net: *Shared context*, *Running tests in parallel*). A Microsoft documenta xUnit apenas via tutoriais; o restante vem de xunit.net. Confirme a versão (v2 vs v3) do projeto; nomes de API de paralelismo mudam na v3. Princípios gerais: `dotnet-unit-testing`; CLI/cobertura: `dotnet-test-automation`.

## Projeto
`dotnet new xunit -o X.Tests` adiciona `Microsoft.NET.Test.Sdk`, `xunit`, `xunit.runner.visualstudio`, `coverlet.collector`. Suporta VSTest e MTP (xUnit v3 tem integração com MTP). Referencie o projeto sob teste com `dotnet add reference`.

## Testes
```csharp
public class PrimeService_IsPrimeShould
{
    [Fact]
    public void IsPrime_InputIs1_ReturnFalse() { /* AAA */ }

    [Theory]
    [InlineData(-1)] [InlineData(0)] [InlineData(1)]
    public void IsPrime_ValuesLessThan2_ReturnFalse(int value) { /* ... */ }
}
```
- `[Fact]` = teste sem parâmetros. `[Theory]` + `[InlineData]` = mesmo teste com várias entradas (evita duplicação). (Outras fontes de dados como `MemberData`/`ClassData` existem na doc do xUnit; consulte antes de detalhar.)
- Asserts: `Assert.Equal`, `Assert.False(result, "mensagem")`, `Assert.Throws<T>`, etc.

## Contexto compartilhado (doc xunit.net)
O xUnit **cria uma nova instância da classe de teste para cada teste**.
| Escopo | Mecanismo | Quando |
|---|---|---|
| Por teste | construtor + `IDisposable.Dispose` | cada teste precisa de estado limpo |
| Por teste, assíncrono | `IAsyncLifetime` (`InitializeAsync`/`DisposeAsync`); construtores não podem ser async | setup/cleanup async (em v3, `DisposeAsync` pode vir só de `IAsyncDisposable`) |
| Por classe | `IClassFixture<T>` injetado no construtor | setup caro compartilhado entre testes de **uma** classe; criado antes do 1º teste, descartado após o último |
| Várias classes | `[CollectionDefinition("X")]` + `ICollectionFixture<T>` + `[Collection("X")]` | compartilhar entre classes; **testes da collection rodam em sequência** |
| Assembly inteiro | `[assembly: AssemblyFixture(typeof(T))]` (**v3**) | uma instância por assembly; **deve ser thread-safe** (paralelismo não muda) |
Fixture de banco (EF Core doc): criado uma vez, com lock se usado por várias classes; ver `efcore-testing`.

## Paralelismo (doc xunit.net)
- Os testes rodam em paralelo **por collection**; por padrão **cada classe é sua própria collection** (`CollectionPerClass`). Testes da mesma collection rodam em série; collections diferentes podem rodar ao mesmo tempo.
- Modos: `none` (tudo serial), `collections` (padrão), `all` (v3 4.0+).
- Para impedir paralelismo entre classes, coloque-as na mesma `[Collection("nome")]`. Collection com `DisableParallelization = true` desliga o paralelismo dela.
- Max de threads: padrão = nº de CPUs; configuração por atributo de assembly (`CollectionBehavior(MaxParallelThreads = n)` em v2; atributo `Parallelization` na v3 4.0+) ou por runner/`xunit.runner.json`.
- Consequência prática: estado estático/banco compartilhado entre classes exige isolamento (transação, banco por fixture) ou collection serial.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `[Fact]` vs `[Theory]` corretos; casos repetidos viraram `InlineData` |
| 2 | Setup no construtor/`IAsyncLifetime`; sem `[SetUp]` (não existe) |
| 3 | Fixture certo para o escopo (class/collection/assembly); thread-safe quando compartilhado |
| 4 | Testes que mexem em estado compartilhado estão na mesma collection ou isolados |
| 5 | Nenhum teste depende de ordem de execução |
| 6 | Testes async retornam `Task` (não `async void`) |
| 7 | Nomes Método_Cenário_Resultado; AAA |
| 8 | Versão do xUnit (v2/v3) considerada nas APIs usadas |

## Fontes oficiais
- Tutorial xUnit com `dotnet test`: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-csharp-with-xunit
- Testing in .NET (visão geral de frameworks): https://learn.microsoft.com/en-us/dotnet/core/testing/
- xUnit — Shared context: https://xunit.net/docs/shared-context
- xUnit — Running tests in parallel: https://xunit.net/docs/running-tests-in-parallel
- xUnit — site oficial: https://xunit.net
