---
name: dotnet-mstest
description: Escrever e revisar testes com MSTest (TestClass, TestMethod, DataRow, DynamicData, CombinatorialData, Assert.ThrowsExactly, lifecycle AssemblyInitialize/ClassInitialize/TestInitialize, Parallelize, Timeout, Retry, TestCategory, TestContext, MSTest.Sdk, runner MTP, runsettings). Use quando o projeto usa MSTest ou o usuário pedir para criar/revisar testes MSTest. Based on official Microsoft Learn docs (MSTest 3.x/4.x).
---

# MSTest — escrever e revisar

Só afirmar o que a doc oficial diz (fontes no fim); versões citadas (3.x/4.x) importam: **confira a versão do pacote do projeto** antes de usar API nova. Princípios gerais: `dotnet-unit-testing`. Estratégia/CLI/cobertura: `dotnet-test-automation`.

## Estrutura básica
```csharp
[TestClass]
public class CalculatorTests
{
    [TestMethod]
    public void Add_TwoNumbers_ReturnsSum()
    {
        var calculator = new Calculator();           // Arrange
        int result = calculator.Add(2, 3);           // Act
        Assert.AreEqual(5, result);                  // Assert
    }
}
```
- Classe com `[TestClass]`; método com `[TestMethod]`. Sufixo `Attribute` é opcional.
- Método de teste: **instância (não static), `public`, retorno `void`/`Task`/`ValueTask` (ValueTask: MSTest 3.3+), sem parâmetros** (salvo atributos data-driven). **Nunca `async void`.**
- Por padrão só testes `public` são descobertos; `[assembly: DiscoverInternals]` descobre `internal` (útil com tipos internos como parâmetros).
- Testar membros privados via `PrivateObject`/`PrivateType` existe, mas a doc sugere avaliar se precisa; **teste pela interface pública**.

## Assertions
- Em código novo **use sempre a classe `Assert`**. `StringAssert` e `CollectionAssert` são mantidas por compatibilidade e **provavelmente serão descontinuadas** (espalhar assertions em 3 tipos prejudica a descoberta).
- Principais: `AreEqual/AreNotEqual`, `AreSame/AreNotSame`, `IsTrue/IsFalse`, `IsNull/IsNotNull`, `IsInstanceOfType<T>`, `Contains/DoesNotContain`, `ContainsSingle`, `HasCount`, `IsEmpty/IsNotEmpty`, `StartsWith/EndsWith`, `MatchesRegex`, `IsGreaterThan/IsLessThan/IsInRange/IsPositive/IsNegative`, `Fail`, `Inconclusive`.
- **Exceções (MSTest 3.8+):** `Assert.Throws<T>`, `Assert.ThrowsExactly<T>` (tipo exato), `ThrowsAsync`, `ThrowsExactlyAsync`.
- **MSTest 4.0+:** todas as `Assert` capturam a expressão do argumento nas mensagens de falha; existe `Assert.That(expr)` (Boolean com `CallerArgumentExpression`).
- Parâmetro opcional `message` é exibido na falha.

## Data-driven
| Atributo | Uso |
|---|---|
| `[DataRow(...)]` | dados inline, estáticos; nº e tipos devem casar com a assinatura; suporta `params`, arrays, `null`; `DisplayName`; `IgnoreMessage` (3.8+) para pular uma linha |
| `[DynamicData(nameof(Dados))]` | dados vindos de método/propriedade/campo `IEnumerable<T>`; tipos aceitos incluem `ValueTuple` (compile-time, simples), `Tuple`, arrays; `TestDataRow<T>` adiciona display name/categorias/ignore por caso |
| `[CombinatorialData]` | produto cartesiano (MSTest **4.4+**); `CombinatorialValues`, `CombinatorialRange`, `CombinatorialRandomData`; não faz pairwise nem exclusões |
| `[DataSource]` | fontes externas (cenário legado) |
- Métodos de teste genéricos a partir do MSTest 3.8 (tipo inferido de `DataRow`/`DynamicData`). `DateOnly`/`TimeOnly` em `DataRow` a partir da 3.10.
- Não copie o teste para variar parâmetro: use `DataRow`.

## Lifecycle (quatro níveis)
1. **Assembly:** `[AssemblyInitialize]`/`[AssemblyCleanup]`.
2. **Classe:** `[ClassInitialize]`/`[ClassCleanup]` (herança via `InheritanceBehavior.BeforeEachDerivedClass`).
3. **Global por teste** (3.10+): `[GlobalTestInitialize]`/`[GlobalTestCleanup]` (ordem entre múltiplos não é garantida).
4. **Por teste:** `[TestInitialize]`/`[TestCleanup]` (por linha de dados em testes parametrizados).
Regras dos de assembly/classe: **`public static`**, retorno `void`/`Task`/`ValueTask`, `Initialize` exige um parâmetro `TestContext`, `Cleanup` aceita zero ou um (3.8+), um de cada por assembly/classe, dentro de classe `[TestClass]`. Falha em cleanup é reportada como resultado separado (4.2+). Test classes podem receber `TestContext` pelo **construtor** (3.6+, preferido à propriedade). MSTest 4.5 (experimental): `MSTest.Extensions.Hosting` cria classes de teste com serviços do `Microsoft.Extensions.Hosting`.

## Execução e controle
- Execução é **sequencial por padrão**. Paralelismo: `[assembly: Parallelize(Workers = 0, Scope = ExecutionScope.MethodLevel|ClassLevel)]` (Workers 0 = nº de processadores lógicos); `[DoNotParallelize]` em classe/método; também via `.runsettings`, `testconfig.json` (`mstest.parallelism.enabled`) e MSBuild (`MSTestParallelizeScope`). A doc recomenda habilitar no assembly por padrão para que testes novos nasçam compatíveis com paralelismo (analyzer MSTEST0001).
- `[Timeout]`, `[Retry]` (`TestContext.TestRunCount` mostra a tentativa), `[Ignore]`, `[OSCondition]`, `[CICondition]`.
- Threading Windows: `[STATestClass]`, `[STATestMethod]` (3.6+; `UseSTASynchronizationContext` 4.1+), `[UITestMethod]` (UWP/WinUI).
- Ordem dos testes: a doc diz que idealmente **a ordem não deve importar**; `OrderTestsByNameInClass` (runsettings, 3.6+) existe, mas ordenação e paralelismo são questões separadas (desative o paralelismo para garantir execução serial).

## Organização/metadados
`[TestCategory("Unit")]` (método, classe ou assembly; combinam), `[TestProperty]`, `[Owner]`, `[Priority(n)]` (menor = mais prioritário), `[Description]` (use o de `Microsoft.VisualStudio.TestTools.UnitTesting`, não o de `System.ComponentModel`), `[WorkItem]`. Filtros: `dotnet test --filter TestCategory=Integration`, `--filter "TestCategory=Integration|TestCategory=Unit"`, `TestCategory!=Slow`.

## TestContext
Propriedades úteis: `TestName`, `CurrentTestOutcome`, `FullyQualifiedTestClassName`, `TestRunDirectory`, `ResultsDirectory`, `DeploymentDirectory`, `TestRunCount` (3.9+), `TestTempDirectory` (diretório temporário único por teste/linha; apagado se passa; `MSTEST_TEST_TEMP_DIRECTORY_RETAIN=1` mantém), `WriteLine`.

## Projeto, SDK e runner
- **MSTest tem runner próprio (desde 3.2.0)**, mais leve/rápido que VSTest e o recomendado; baseado em MTP.
- **`MSTest.Sdk`** substitui `Microsoft.NET.Sdk` e **liga o runner MTP por padrão** (`EnableMSTestRunner` e `TestingPlatformDotnetTestSupport` = true). Volte ao VSTest com `<UseVSTest>true</UseVSTest>`. Não funciona onde se precisa de outro SDK base (ex.: `Microsoft.NET.Sdk.Web` em testes de integração): configure manualmente (`EnableMSTestRunner`, `OutputType=Exe`, pacote `MSTest`).
- Meta-pacote `MSTest` = `Microsoft.NET.Test.Sdk` + `MSTest.TestAdapter` + `MSTest.TestFramework` + `MSTest.Analyzers` (+ TrxReport e CodeCoverage a partir da 3.8).
- Perfis de extensões MTP no SDK (`TestingExtensionsProfile`): `None`, `Default` (Code Coverage, TRX, Azure DevOps, GitHub Actions), `AllMicrosoft` (+ Crash/Hang dump, Fakes, Hot Reload, HTML, Retry; licença restritiva em algumas).
- Defina `EnableMSTestRunner`/`TestingPlatformDotnetTestSupport` no `Directory.Build.props` para toda a solution.
- Plataformas: .NET 8+, .NET Framework 4.6.2+, UWP/WinUI (com `UITestMethod`), Native AOT (conjunto limitado), WebAssembly (limitado). 
- **MSTest.Analyzers** (MSTESTxxxx) detectam erros de assinatura de lifecycle, `DataRow` incompatível, `DataRow` duplicado etc.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `[TestClass]`/`[TestMethod]` corretos; método público, instância, não `async void` |
| 2 | Assert via `Assert` (não `StringAssert`/`CollectionAssert` em código novo) |
| 3 | `ThrowsExactly` em vez de `[ExpectedException]`/try-catch manual (3.8+) |
| 4 | `DataRow`/`DynamicData` em vez de testes copiados |
| 5 | Lifecycle com assinatura correta (public static + TestContext) |
| 6 | Estado compartilhado entre testes e ordem implícita → remover |
| 7 | Paralelismo habilitado conscientemente; `DoNotParallelize` só onde necessário |
| 8 | Categorias (`Unit`/`Integration`) para filtrar no CI |
| 9 | Runner/SDK coerente (MTP vs VSTest) com `dotnet test` e CI; analyzers ativos |
| 10 | Versão do MSTest compatível com os atributos usados |

## Fontes oficiais
- MSTest overview: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-intro
- Write tests: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests
- Assertions: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests-assertions
- Data-driven: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests-data-driven
- Lifecycle: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests-lifecycle
- Execution control: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests-controlling-execution
- Organizing: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests-organizing
- TestContext: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-writing-tests-testcontext
- Run tests (runner): https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-running-tests
- MSTest.Sdk: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-mstest-sdk
- Order tests: https://learn.microsoft.com/en-us/dotnet/core/testing/order-unit-tests
