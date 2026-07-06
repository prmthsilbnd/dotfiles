return {
	{
		"RRethy/base16-nvim",
		priority = 1000,
		config = function()
			require('base16-colorscheme').setup({
				base00 = '#1d1d20',
				base01 = '#1d1d20',
				base02 = '#7a7d82',
				base03 = '#7a7d82',
				base04 = '#94989d',
				base05 = '#d4d6d9',
				base06 = '#d4d6d9',
				base07 = '#d4d6d9',
				base08 = '#ca7e95',
				base09 = '#ca7e95',
				base0A = '#8093a5',
				base0B = '#75b47d',
				base0C = '#b9c6d2',
				base0D = '#8093a5',
				base0E = '#9fb1c3',
				base0F = '#9fb1c3',
			})

			vim.api.nvim_set_hl(0, 'Visual', {
				bg = '#7a7d82',
				fg = '#d4d6d9',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Statusline', {
				bg = '#8093a5',
				fg = '#1d1d20',
			})
			vim.api.nvim_set_hl(0, 'LineNr', { fg = '#7a7d82' })
			vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#b9c6d2', bold = true })

			vim.api.nvim_set_hl(0, 'Statement', {
				fg = '#9fb1c3',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Keyword', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Repeat', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Conditional', { link = 'Statement' })

			vim.api.nvim_set_hl(0, 'Function', {
				fg = '#8093a5',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Macro', {
				fg = '#8093a5',
				italic = true
			})
			vim.api.nvim_set_hl(0, '@function.macro', { link = 'Macro' })

			vim.api.nvim_set_hl(0, 'Type', {
				fg = '#b9c6d2',
				bold = true,
				italic = true
			})
			vim.api.nvim_set_hl(0, 'Structure', { link = 'Type' })

			vim.api.nvim_set_hl(0, 'String', {
				fg = '#75b47d',
				italic = true
			})

			vim.api.nvim_set_hl(0, 'Operator', { fg = '#94989d' })
			vim.api.nvim_set_hl(0, 'Delimiter', { fg = '#94989d' })
			vim.api.nvim_set_hl(0, '@punctuation.bracket', { link = 'Delimiter' })
			vim.api.nvim_set_hl(0, '@punctuation.delimiter', { link = 'Delimiter' })

			vim.api.nvim_set_hl(0, 'Comment', {
				fg = '#7a7d82',
				italic = true
			})

			local current_file_path = vim.fn.stdpath("config") .. "/lua/plugins/dankcolors.lua"
			if not _G._matugen_theme_watcher then
				local uv = vim.uv or vim.loop
				_G._matugen_theme_watcher = uv.new_fs_event()
				_G._matugen_theme_watcher:start(current_file_path, {}, vim.schedule_wrap(function()
					local new_spec = dofile(current_file_path)
					if new_spec and new_spec[1] and new_spec[1].config then
						new_spec[1].config()
						print("Theme reload")
					end
				end))
			end
		end
	}
}
