# dpp-ext-lazy

This ext implements lazy loading.

## Required

### denops.vim

https://github.com/vim-denops/denops.vim

### dpp.vim

https://github.com/Shougo/dpp.vim

## Configuration

```typescript
const [context, options] = await args.contextBuilder.get(args.denops);

// Get plugins from other exts
const plugins = ...

const stateLines = await args.dpp.extAction(
  args.denops,
  context,
  options,
  "lazy",
  "makeState",
  {
    plugins,
  },
) as string[];
```
