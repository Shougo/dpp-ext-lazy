import {
  Actions,
  BaseExt,
  Plugin,
} from "https://deno.land/x/dpp_vim@v0.0.4/types.ts";
import { Denops } from "https://deno.land/x/dpp_vim@v0.0.4/deps.ts";

type Params = Record<string, never>;

type LazyMakeStateArgs = {
  plugins: Plugin[];
};

type LazyMakeStateResult = {
  plugins: Plugin[];
  stateLines: string[];
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
        const params = args.actionParams as LazyMakeStateArgs;

        let stateLines = StateLines;

        type dummyResult = {
          dummys: string[];
          stateLines: string[];
        };

        for (const plugin of params.plugins.filter((plugin) => plugin.lazy)) {
          const dummyCommands = await args.denops.call(
            "dpp#ext#lazy#_generate_dummy_commands",
            plugin,
          ) as dummyResult;
          if (dummyCommands.dummys.length > 0) {
            plugin.dummy_commands = dummyCommands.dummys;
          }
          if (dummyCommands.stateLines.length > 0) {
            stateLines = stateLines.concat(dummyCommands.stateLines);
          }

          const dummyMappings = await args.denops.call(
            "dpp#ext#lazy#_generate_dummy_mappings",
            plugin,
          ) as dummyResult;
          if (dummyMappings.stateLines.length > 0) {
            stateLines = stateLines.concat(dummyMappings.stateLines);
          }
          if (dummyMappings.dummys.length > 0) {
            plugin.dummy_mappings = dummyMappings.dummys;
          }

          if ("on_lua" in plugin) {
            stateLines = stateLines.concat(
              await args.denops.call(
                "dpp#ext#lazy#_generate_on_lua",
                plugin,
              ) as string[],
            );
          }
        }

        return {
          plugins: params.plugins,
          stateLines,
        } satisfies LazyMakeStateResult;
      },
    },
  };

  override params(): Params {
    return {};
  }
}
