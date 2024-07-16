# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule Watermelon.Case do
  @moduledoc """
  Helpers for generating feature test modules.

  This module needs to be used within your `ExUnit.Case` module to provide
  functionalities needed for building feature tests within your regular `ExUnit`
  tests.

  For documentation about defining steps, check out `Watermelon.DSL`.

  ## Example

  ```elixir
  defmodule MyApp.FeatureTest do
    use ExUnit.Case, async: true
    use #{inspect(__MODULE__)}

    feature \"\"\"
    Feature: Example
      Scenario: simple test
        Given empty stack
        And pushed 1
        And pushed 2
        When execute sum function
        Then have 3 on top of stack
    \"\"\"

    defgiven match when "empty stack", do: {:ok, stack: []}

    defgiven match(val) when "pushed {num}", context: %{stack: stack} do
      {:ok, stack: [val | stack]}
    end

    defwhen match when "execute sum function", context: ctx do
      assert [a, b | rest] = ctx.stack

      {:ok, stack: [a + b | rest]}
    end

    defthen match(result) when "have {num} on top of stack", context: ctx do
      assert [^result | _] = ctx.stack
    end
  end
  ```

  Which is rough equivalent of:

  ```elixir
  defmodule MyApp.FeatureTest do
    use ExUnit.Case, async: true

    test "simple test" do
      stack = [1, 2]
      assert [a, b | _] = stack
      assert 3 == a + b
    end
  end
  ```

  ## Importing steps from different modules

  In time amount of steps can grow and grow, and a lot of them will repeat between
  different tests, so for your convenience `#{inspect(__MODULE__)}` provide a way for
  importing steps definitions from other modules via setting `@step_modules` module
  attribute. For example to split above steps we can use:

  ```elixir
  defmodule MyApp.FeatureTest do
    use ExUnit.Case, async: true
    use #{inspect(__MODULE__)}

    @step_modules [
      MyApp.StackSteps
    ]

    feature_file "stack.feature"
  end
  ```

  ## Setup and teardown

  Nothing special there, just use old `ExUnit.Callbacks.setup/2`
  or `ExUnit.Callbacks.setup_all/2` like in any other of Your test modules.
  """

  alias Gherkin.Elements, as: G

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Watermelon.DSL

      import unquote(__MODULE__), only: [feature: 1, feature_file: 1]

      @step_modules []
    end
  end

  @doc """
  Define inline feature description.

  It accepts inline feature description declaration.

  ## Example

  ```elixir
  defmodule ExampleTest do
    use ExUnit.Case
    use #{inspect(__MODULE__)}

    feature \"\"\"
    Feature: Inline feature
      Scenario: Example
        Given foo
        When bar
        Then baz
    \"\"\"

    # Steps definitions
  end
  ```
  """
  defmacro feature(string) do
    feature = Gherkin.parse(string)

    generate_feature_test(feature, __CALLER__)
  end

  @doc """
  Load file from features directory.

  Default features directory is set to `test/features`, however you can change
  it by setting `config :watermelon, features_path: "my_features_dir/"` in your
  configuration file.

  ## Example

  ```elixir
  defmodule ExampleTest do
    use ExUnit.Case
    use #{inspect(__MODULE__)}

    feature_file "my_feature.feature"

    # Steps definitions
  end
  ```
  """
  defmacro feature_file(filename) do
    root = Application.get_env(:watermelon, :features_path, "test/features")
    path = Path.expand(filename, root)
    feature = Gherkin.parse_file(path)

    Module.put_attribute(__CALLER__.module, :external_attribute, filename)

    generate_feature_test(feature, __CALLER__)
  end

  defp generate_feature_test(feature, _env) do
    quote location: :keep, bind_quoted: [feature: Macro.escape(feature)] do
      describe "#{feature.name}" do
        step_modules =
          case Module.get_attribute(__MODULE__, :step_modules, []) do
            modules when is_list(modules) -> [__MODULE__ | modules]
            _ -> raise "@step_modules, if set, must be list"
          end

        @tag Enum.map(feature.tags, &{&1, true})

        setup context do
          Watermelon.Case.run_steps(
            unquote(Macro.escape(feature.background_steps)),
            context,
            unquote(step_modules)
          )
        end

        for %{name: scenario_name, steps: steps, tags: tags} <- Watermelon.Case.scenarios(feature) do
          name =
            ExUnit.Case.register_test(
              __ENV__.module,
              __ENV__.file,
              __ENV__.line,
              :scenario,
              "#{scenario_name}",
              tags
            )

          def unquote(name)(context) do
            Watermelon.Case.run_steps(
              unquote(Macro.escape(steps)),
              Map.put(context, :scenario_name, unquote(Macro.escape(scenario_name))),
              unquote(step_modules)
            )
          end
        end
      end
    end
  end

  def scenarios(%G.Feature{scenarios: scenarios}) do
    Enum.flat_map(scenarios, fn
      %G.Scenario{} = s -> [s]
      %G.ScenarioOutline{} = outline -> Gherkin.scenarios_for(outline)
    end)
  end

  @doc false
  def run_steps(steps, context, modules) do
    {context, _cursor} =
      Enum.reduce(steps, {context, 0}, fn step, {context, cursor} ->
        modules
        |> Enum.find_value(:missing_definition, fn module ->
          try do
            step(module, step, context)
          rescue
            e ->
              msg = get_error_message(e)

              raise_error(context.scenario_name, steps, cursor, msg, __STACKTRACE__)
          end
        end)
        |> case do
          {_, {:ok, context}} ->
            {context, cursor + 1}

          {_, other} ->
            raise_error(
              context.scenario_name,
              steps,
              cursor,
              "Unexpected return value `#{inspect(other)}`"
            )

          :missing_definition ->
            raise_error(
              context.scenario_name,
              steps,
              cursor,
              "Definition for \"#{step.text}\" not found"
            )
        end
      end)

    context
  end

  defp step(module, step, context) do
    case module.apply_step(step, context) do
      {:ok, _} = return -> return
      :error -> false
    end
  end

  defp get_error_message(%mod{} = e) do
    try do
      mod.message(e)
    rescue
      _ -> Exception.message(e)
    end
  end

  defp get_error_message(e), do: Exception.message(e)

  defp raise_error(scenario_name, steps, cursor, error_msg, stacktrace \\ []) do
    {previous, [current | next]} =
      steps
      |> Enum.map(&(String.pad_leading(get_step_type(&1), 5, " ") <> " " <> &1.text))
      |> Enum.split(cursor)

    printable_steps =
      List.flatten([
        Enum.map(previous, &(green("✓") <> "\s\t" <> &1)),
        red("✕") <> "\s\t" <> red(current),
        Enum.map(next, &("⊘\s\t" <> &1))
      ])
      |> Enum.join("\n")

    str = IO.ANSI.reset() <> printable_steps
    delimiter = IO.ANSI.reset() <> "---"

    msg = """
    #{error_msg}

    #{delimiter}
    \s\sScenario: #{scenario_name}
    #{str}
    """

    reraise RuntimeError, msg, stacktrace
  end

  defp color(text, color), do: color <> text <> IO.ANSI.reset()
  defp green(text), do: color(text, IO.ANSI.green())
  defp red(text), do: color(text, IO.ANSI.red())

  defp get_step_type(step) do
    [step_type | _] =
      Atom.to_string(step.__struct__)
      |> String.split(".")
      |> Enum.reverse()
      |> Enum.map(&String.capitalize/1)

    step_type
  end
end
