local common = require("insis.lsp.common-config")
local opts = {
  capabilities = common.capabilities,
  flags = common.flags,
  on_attach = function(client, bufnr)
    common.disableFormat(client)
    common.keyAttach(bufnr)
  end,
  settings = {
    pylsp = {
      plugins = {
        pycodestyle = {
          ignore = { "E266", "E402", "E501", "E741", "W291", "W391", "W501", "W503", "W504" },
          maxLineLength = 100,
        },
      },
    },
  },
}
return {
  on_setup = function(server)
    server.setup(opts)
  end,
}
