import {
  type Actions,
  BaseExt,
  type Denops,
  type Plugin,
} from "jsr:@shougo/dpp-vim@2.1.0/types";
import { convert2List, printError } from "jsr:@shougo/dpp-vim@2.1.0/utils";

import * as fn from "jsr:@denops/std@7.0.3/function";

type Params = Record<string, never>;

type LazyMakeStateArgs = {
  plugins: Plugin[];
};

type LazyMakeStateResult = {
  plugins: Plugin[];
  stateLines: string[];
};

const StateLines = [
  "augroup dpp-ext-lazy",
  "  autocmd!",
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

        type dummyMappingsResult = {
          dummys: [string, string][];
          stateLines: string[];
        };

        type dummyCommandsResult = {
          dummys: string[];
          stateLines: string[];
        };

        // NOTE: lazy flag may be not set.
        const lazyPlugins = params.plugins.filter((plugin) =>
          plugin.lazy ||
          Object.keys(plugin).filter((k) => k.startsWith("on_")).length > 0
        );

        // NOTE: on_map should be loaded on SafeState.
        stateLines = stateLines.concat([
          "function! s:define_on_map() abort",
        ]);
        const checkDummyMaps: Map<string, Set<string>> = new Map();
        for (const plugin of lazyPlugins) {
          const dummyMappings = await args.denops.call(
            "dpp#ext#lazy#_generate_dummy_mappings",
            plugin,
          ) as dummyMappingsResult;
          if (dummyMappings.stateLines.length > 0) {
            stateLines = stateLines.concat(dummyMappings.stateLines);
          }
          if (dummyMappings.dummys.length > 0) {
            plugin.dummy_mappings = dummyMappings.dummys;

            for (const [mode, map] of dummyMappings.dummys) {
              if (!checkDummyMaps.get(mode)) {
                checkDummyMaps.set(mode, new Set());
              }

              const check = checkDummyMaps.get(mode);
              if (check) {
                if (check.has(map)) {
                  await printError(
                    args.denops,
                    `Duplicated on_map is detected: "${map}" for mode "${mode}" in "${plugin.name}"`,
                  );
                } else {
                  check.add(map);
                }
              }
            }
          }
        }
        stateLines = stateLines.concat([
          "endfunction",
          "autocmd dpp-ext-lazy SafeState * ++once call s:define_on_map()",
        ]);

        const existsEventPlugins: Record<string, boolean> = {};
        const checkDummyCommands: Set<string> = new Set();
        for (const plugin of lazyPlugins) {
          const dummyCommands = await args.denops.call(
            "dpp#ext#lazy#_generate_dummy_commands",
            plugin,
          ) as dummyCommandsResult;
          if (dummyCommands.dummys.length > 0) {
            plugin.dummy_commands = dummyCommands.dummys;
            for (const command of dummyCommands.dummys) {
              if (checkDummyCommands.has(command)) {
                await printError(
                  args.denops,
                  `Duplicated on_cmd is detected: "${command}" in "${plugin.name}"`,
                );
              } else {
                checkDummyCommands.add(command);
              }
            }
          }
          if (dummyCommands.stateLines.length > 0) {
            stateLines = stateLines.concat(dummyCommands.stateLines);
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
              `autocmd dpp-ext-lazy ${event} * call dpp#ext#lazy#_on_event('${event}')`,
            );
          } else {
            // It is User events
            stateLines.push(
              `autocmd dpp-ext-lazy User ${event} call dpp#ext#lazy#_on_event('${event}')`,
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
