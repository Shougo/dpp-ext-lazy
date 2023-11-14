# dpp-ext-lazy

This ext implements lazy loading.

## Required

### denops.vim

https://github.com/vim-denops/denops.vim

### dpp.vim

https://github.com/Shougo/dpp.vim

## Configuration

```typescript
type LazyMakeStateResult = {
  plugins: Plugin[];
  stateLines: string[];
};

const [context, options] = await args.contextBuilder.get(args.denops);

// Get plugins from other exts
const plugins = ...

const lazyResult = await args.dpp.extAction(
  args.denops,
  context,
  options,
  "lazy",
  "makeState",
  {
    plugins: Object.values(recordPlugins),
  },
) as LazyMakeStateResult | undefined;
```
