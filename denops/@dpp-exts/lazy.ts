import { Actions, BaseExt, Plugin } from "https://deno.land/x/dpp_vim@v0.0.3/types.ts";
import { Denops } from "https://deno.land/x/dpp_vim@v0.0.3/deps.ts";

type Params = Record<string, never>;

type MakeStateArgs = {
  plugins: Plugin[];
};

const StateLines = [
  "augroup dpp",
  "  autocmd FuncUndefined *",
  "       \\ : if '<afile>'->expand()->stridx('remote#') != 0",
  "       \\ |   call dpp#ext#lazy#_on_func('<afile>'->expand())",
  "       \\ | endif",
  " autocmd BufRead *? call dpp#ext#lazy#_on_default_event('BufRead')",
  " autocmd BufNew,BufNewFile *? call dpp#ext#lazy#_on_default_event('BufNew')",
  " autocmd VimEnter *? call dpp#ext#lazy#_on_default_event('VimEnter')",
  " autocmd FileType *? call dpp#ext#lazy#_on_default_event('FileType')",
  " autocmd CmdUndefined * call dpp#ext#lazy#_on_pre_cmd('<afile>'->expand())",
  "augroup END",
  "augroup dpp-events | augroup END",
  "if has('nvim')",
  "let g:dpp#_on_lua_plugins = {}",
  "lua <<END",
  "table.insert(package.loaders, 1, (function()",
  "  return function(mod_name)",
  "    mod_root = string.match(mod_name, '^[^./]+')",
  "    if vim.g['dpp#_on_lua_plugins'][mod_root] then",
  "      vim.fn['dpp#ext#lazy#_on_lua'](mod_name)",
  "    end",
  "    if package.loaded[mod_name] ~= nil then",
  "      local m = package.loaded[mod_name]",
  "      return function()",
  "        return m",
  "      end",
  "    end",
  "    return nil",
  "  end",
  "end)())",
  "END",
  "endif",
];

export class Ext extends BaseExt<Params> {
  override actions: Actions<Params> = {
    makeState: {
      description: "Make stateLines",
      callback: async (args: {
        denops: Denops;
        actionParams: unknown;
      }) => {
        const params = args.actionParams as MakeStateArgs;

        let stateLines = StateLines;

        for (const plugin of params.plugins.filter((plugin) => plugin.lazy)) {
          stateLines = stateLines.concat(
            await args.denops.call(
              "dpp#ext#lazy#_generate_dummy_commands",
              plugin,
            ) as string[],
          );
          stateLines = stateLines.concat(
            await args.denops.call(
              "dpp#ext#lazy#_generate_dummy_mappings",
              plugin,
            ) as string[],
          );

          if ("on_lua" in plugin) {
            stateLines = stateLines.concat(
              await args.denops.call(
                "dpp#ext#lazy#_generate_on_lua",
                plugin,
              ) as string[],
            );
          }
        }

        console.log(stateLines);
        return stateLines;
      },
    },
  };

  override params(): Params {
    return {};
  }
}
