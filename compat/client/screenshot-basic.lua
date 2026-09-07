-- `provide 'screenshot-basic'` only satisfies dependency checks. This late
-- hook (after modules/** has populated QB.screenshot and exports.lua has
-- created QB.compat.provideExport) preserves the resource identity that
-- existing clients use: exports['screenshot-basic']:requestScreenshot(...).
QB.compat.provideExport('screenshot-basic', 'requestScreenshot', QB.screenshot.requestScreenshot)
QB.compat.provideExport('screenshot-basic', 'requestScreenshotUpload', QB.screenshot.requestScreenshotUpload)
