import {
  Actions,
  BaseExt,
  Plugin,
} from "https://deno.land/x/dpp_vim@v0.0.7/types.ts";
import { Denops, fn } from "https://deno.land/x/dpp_vim@v0.0.7/deps.ts";
import { convert2List } from "https://deno.land/x/dpp_vim@v0.0.7/utils.ts";

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
  "let g:dpp#ext#_on_lua_plugins = {}",
  "let g:dpp#ext#_called_lua = {}",
  "lua <<END",
  "table.insert(package.loaders, 1, (function()",
  "  return function(mod_name)",
  "    mod_root = string.match(mod_name, '^[^./]+')",
  "    if vim.g['dpp#ext#_on_lua_plugins'][mod_root] then",
  "      vim.fn['dpp#ext#lazy#_on_lua'](mod_name, mod_root)",
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

        // NOTE: lazy flag may be not set.
        const lazyPlugins = params.plugins.filter((plugin) =>
          plugin.lazy ||
          Object.keys(plugin).filter((k) => k.startsWith("on_")).length > 0
        );
        const existsEventPlugins: Record<string, boolean> = {};
        for (const plugin of lazyPlugins) {
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

          if ("on_event" in plugin) {
            for (
              const event of convert2List(plugin.on_event).filter(
                (event) => !existsEventPlugins[event],
              )
            ) {
              existsEventPlugins[event] = true;
            }
          }
        }

        for (const event of Object.keys(existsEventPlugins)) {
          if (await fn.exists(args.denops, `##${event}`)) {
            stateLines.push(
              `autocmd dpp-events ${event} * call dpp#ext#lazy#_on_event('${event}')`,
            );
          } else {
            // It is User events
            stateLines.push(
              `autocmd dpp-events User ${event} call dpp#ext#lazy#_on_event('${event}')`,
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
