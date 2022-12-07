local t = ...


----------------------------------------------------------------------------------------------------------------------
--
-- ActionDocBuilder
--

local function __lustache_runInSandbox(atValues, strCode)
  local compat = require 'pl.compat'

  -- Create a sandbox.
  local atEnv = {
    ['error']=error,
    ['ipairs']=ipairs,
    ['next']=next,
    ['pairs']=pairs,
    ['print']=print,
    ['select']=select,
    ['tonumber']=tonumber,
    ['tostring']=tostring,
    ['type']=type,
    ['math']=math,
    ['string']=string,
    ['table']=table
  }
  for strKey, tValue in pairs(atValues) do
    atEnv[strKey] = tValue
  end
  local tFn, strError = compat.load(strCode, 'parser code', 't', atEnv)
  if tFn==nil then
    return nil, string.format('Parse error in code "%s": %s', strCode, tostring(strError))
  else
    local fRun, fResult = pcall(tFn)
    if fRun==false then
      return nil, string.format('Failed to run the code "%s": %s', strCode, tostring(fResult))
    else
      return fResult
    end
  end
end



local function __lustache_createView(atConfiguration, atVariables, atExtension)
  local tablex = require 'pl.tablex'

  -- Create a new copy of the variables.
  local atView = tablex.deepcopy(atVariables)

  -- Add the commom methods.
  atView['if'] = function(text, render, context)
    local strResult
    -- Extract the condition.
    local strCondition, strText = string.match(text, '^%{%{([^}]+)%}%}(.*)')
    local strCode = 'return ' .. strCondition
    local fResult, strConditionError = __lustache_runInSandbox(context, strCode)
    if fResult==nil then
      strResult = string.format('ERROR in if condition: %s', strConditionError)
    else
      if fResult==true then
        strResult = render(strText)
      end
    end
    return strResult
  end

  atView['import'] = function(text, render, context)
    local path = require 'pl.path'
    local strFile = render(text)
    -- Append the filename to the list of files.
    local strImportFilename = path.abspath(strFile, path.dirname(atConfiguration.strCurrentDocument))
    if string.sub(strImportFilename, -string.len(atConfiguration.strSuffix))==atConfiguration.strSuffix then
      table.insert(atConfiguration.atFiles, {
        path = strImportFilename,
        view = context
      })
    end
    local strFilteredFilename = string.sub(
      strFile,
      1,
      string.len(strFile) - string.len(atConfiguration.strSuffix)
    ) .. atConfiguration.ext
    local strResult = string.format(
      ':imagesdir: %s\ninclude::%s[]',
      path.dirname(strFile),
      strFilteredFilename
    )

    return strResult
  end

  if atExtension~=nil then
    tablex.update(atView, atExtension)
  end

  return atView
end



local function actionDocBuilder(tInstallHelper)
  local tResult = true
  local pl = tInstallHelper.pl
  local tLog = tInstallHelper.tLog

  local atConfiguration = {
    root = 'main',
    ext = '.asciidoc',
    strSuffix = '.mustache.asciidoc',
    strCurrentDocument = nil,
    atFiles = {}
  }

  local atRootView = {
    test_steps = {}
  }

  local strTestsFile = 'tests.xml'
  if pl.path.exists(strTestsFile)~=strTestsFile then
    tLog.error('The test configuration file "%s" does not exist.', strTestsFile)
    tResult = nil
  elseif pl.path.isfile(strTestsFile)~=true then
    tLog.error('The path "%s" is no regular file.', strTestsFile)
    tResult = nil
  else
    tLog.debug('Parsing tests file "%s".', strTestsFile)
    local tTestDescription = require 'test_description'(tLog)
    local tParseResult = tTestDescription:parse(strTestsFile)
    if tParseResult~=true then
      tLog.error('Failed to parse the test configuration file "%s".', strTestsFile)
      tResult = nil
    else
      atRootView.test_title = tTestDescription:getTitle()
      atRootView.test_subtitle = tTestDescription:getSubtitle()

      -- Copy all documentation links.
      atRootView.documentation_links = tTestDescription:getDocuments()

      -- Collect the documentation for all test cases.
      local uiTestCaseStepMax = tTestDescription:getNumberOfTests()
      for uiTestCaseStepCnt = 1,uiTestCaseStepMax do
        local strTestCaseName = tTestDescription:getTestCaseName(uiTestCaseStepCnt)
        local strDocPath
        local strParameterPath

        local strTestCaseId = tTestDescription:getTestCaseId(uiTestCaseStepCnt)
        local strTestCaseFile = tTestDescription:getTestCaseFile(uiTestCaseStepCnt)
        if strTestCaseId~=nil then
          -- Get the path where the source documentation is copied to.
          strDocPath = pl.path.join(
            strTestCaseId,
            'teststep' .. atConfiguration.strSuffix
          )
          local strDocPathAbs = pl.path.abspath(strDocPath, tInstallHelper:replace_template('${build_doc}'))
          tLog.debug('Looking for documentation in "%s".', strDocPathAbs)
          if pl.path.exists(strDocPathAbs)~=strDocPathAbs then
            tLog.warning('The test %s has no documentation.', strTestCaseName)
            strDocPath = nil
          end

          -- Get the installation path of the parameter file.
          strParameterPath = pl.path.join(
            tInstallHelper:replace_template('${install_base}/parameter/'),
            strTestCaseId .. '.json'
          )
          tLog.debug('Looking for parameter in "%s".', strParameterPath)
          if pl.path.exists(strParameterPath)~=strParameterPath then
            tLog.warning('The test %s has no parameter file.', strTestCaseName)
            strParameterPath = nil
          end
        elseif strTestCaseFile~=nil then

          strDocPath = tTestDescription:getTestCaseDoc(uiTestCaseStepCnt)
          if strDocPath==nil or strDocPath=='' then
            tLog.warning('The test %s has no documentation.', strTestCaseName)
            strDocPath = nil
          elseif pl.path.exists(strDocPath)~=strDocPath then
            tLog.warning('The specified documentation "%s" for test %s does not exist.', strDocPath, strTestCaseName)
            strDocPath = nil
          else
            tLog.debug('Found documentation in "%s".', strDocPath)
          end


        else
          tLog.error('The test %s has no "id" or "file" attribute.', strTestCaseName)
          tResult = nil
          break

        end

        local tParameter = {}
        local tViewAttr = {
          docfile = strDocPath,
          name = strTestCaseName,
          parameter = tParameter
        }
        -- Set all default parameter.
        if strParameterPath~=nil then
          -- Try to read the file.
          local strParameterData, strParameterReadError = pl.utils.readfile(strParameterPath, false)
          if strParameterData==nil then
            tLog.error(
              'Failed to read the parameter file "%s" for test %s: %s',
              strParameterPath,
              strTestCaseName,
              strParameterReadError
            )
          else
            -- Read the parameter JSON and extract all default values.
            local cjson = require 'cjson.safe'
            -- Activate "array" support. This is necessary for the "required" attribute in schemata.
            cjson.decode_array_with_array_mt(true)
            -- Read the parameter file.
            local tParameterData, strParameterParseError = cjson.decode(strParameterData)
            if tParameterData==nil then
              tLog.error(
                'Failed to parse the parameter file "%s" for test %s: %s',
                strParameterPath,
                strTestCaseName,
                strParameterParseError
              )
            else
              -- TODO: validate the parameter data with a schema?

              -- Iterate over all parameters and add them with optional default values to the lookup table.
              for _, tAttr in ipairs(tParameterData.parameter) do
                local strName = tAttr.name
                local tP = {
                  name = strName
                }
                local strDefault = tAttr.default
                if strDefault~=nil then
                  tP.type = 'default'
                  tP.value = strDefault
                  tP.default = strDefault
                end
                tParameter[strName] = tP
              end
            end
          end
        end
        -- Add all parameter from the test description.
        local atTestCaseParameter = tTestDescription:getTestCaseParameters(uiTestCaseStepCnt)
        for _, tEntry in ipairs(atTestCaseParameter) do
          local strName = tEntry.name
          local tP = tParameter[strName]
          if tP==nil then
            tP = {
              name = strName
            }
            tParameter[strName] = tP
          end
          if tEntry.value~=nil then
            tP.type = 'constant'
            tP.value = tEntry.value
          elseif tEntry.connection~=nil then
            tP.type = 'connection'
            tP.value = tEntry.connection
          end
        end

        table.insert(atRootView.test_steps, tViewAttr)
      end
    end
  end

  if tResult==true then
    -- DEBUG: Show the view.
    pl.pretty.dump(atRootView)

    -- Get lustache.
    local lustache = require 'lustache'

    -- Inject the root template.
    table.insert(atConfiguration.atFiles, {
      path = pl.path.join(
        tInstallHelper:replace_template('${build_doc}'),
        atConfiguration.root .. atConfiguration.strSuffix
      ),
      view = atRootView
    })

    while #atConfiguration.atFiles ~= 0 do
      -- Get the first entry from the list.
      local tEntry = table.remove(atConfiguration.atFiles, 1)
      local strTemplateFilename = tEntry.path
      atConfiguration.strCurrentDocument = strTemplateFilename
      tLog.debug('Processing %s ...', strTemplateFilename)
      -- Only process files with the requires suffix.
      if string.sub(strTemplateFilename, -string.len(atConfiguration.strSuffix))==atConfiguration.strSuffix then
        local strTemplate, strTemplateError = pl.utils.readfile(strTemplateFilename, false)
        if strTemplate==nil then
          error(string.format('Failed to read "%s": %s', strTemplateFilename, strTemplateError))
        end

        -- Read an optional view extension.
        local atViewExtension = nil
        local strViewPath = pl.path.join(pl.path.dirname(strTemplateFilename), 'view.lua')
        if pl.path.exists(strViewPath)==strViewPath and pl.path.isfile(strViewPath)==true then
          local strView, strViewError = pl.utils.readfile(strViewPath, false)
          if strView==nil then
            error(string.format('Failed to read "%s": %s', strViewPath, strViewError))
          end
          local strCode = 'return ' .. strView
          local fResult, strError = __lustache_runInSandbox({}, strCode)
          if fResult==nil then
            error(string.format('ERROR in view: %s', tostring(strError)))
          elseif type(fResult)~='table' then
            error(string.format('view returned strange result: %s', tostring(fResult)))
          else
            atViewExtension = fResult
          end
        end

        -- Create a new view.
        local atView = __lustache_createView(atConfiguration, tEntry.view, atViewExtension)

        local strOutput = lustache:render(strTemplate, atView)

        -- Write the output file to the same folder as the input file.
        local strOutputFilename = string.sub(
          strTemplateFilename,
          1,
          string.len(strTemplateFilename) - string.len(atConfiguration.strSuffix)
        ) .. atConfiguration.ext

        pl.utils.writefile(strOutputFilename, strOutput, false)
      end
    end
  end

  if tResult==true then
--[[
    -- Create the HTML output folder if it does not exist yet.
    local strHtmlOutputPath = pl.path.join(
      tInstallHelper:replace_template('${build_doc}'),
      'generated',
      'html'
    )
--]]
    -- Get the source path.
    local strAsciidocSourcePath = tInstallHelper:replace_template('${build_doc}')

    -- Get the output path for the PDF file.
    -- NOTE: This must be a path relative to the source path. It is passed to the container, so absolute paths from the
    --       host OS will not be valid.
    local strPdfRelativeOutputPath = pl.path.join(
      'generated',
      'pdf'
    )

    -- Set the output file.
    local strPdfOutputFile = 'main.pdf'

    -- Build the documentation with AsciiDoctor.
    local astrCommand = {
      -- Run the command in a container.
      'podman',
      'run',
      -- Remove any existing container instances.
      '--rm',
      -- Mount the documentation source path.
      '-v', string.format('%s:/documents/', strAsciidocSourcePath),
      -- Use the "docker-asciidoctor" image.
      'docker.io/asciidoctor/docker-asciidoctor',

      'asciidoctor',

      -- Require some extensions.
      '--require', 'asciidoctor-pdf',
      '--require', 'asciidoctor-diagram',

      -- Generate a PDF.
      '--backend', 'pdf',

      -- Create an article.
      '--doctype', 'article',

      -- Set the output file relative to the source path.
      string.format(
        '--out-file=%s',
        pl.path.join(
          strPdfRelativeOutputPath,
          strPdfOutputFile
        )
      ),

      -- Set the input document.
      atConfiguration.root .. atConfiguration.ext
    }
    local strCommand = table.concat(astrCommand, ' ')
    local tResultDoc = os.execute(strCommand)
    if tResultDoc~=true then
      error(string.format('Failed to generate the documentation with the command "%s".', strCommand))
    end
  end

  return tResult
end

----------------------------------------------------------------------------------------------------------------------


local tResult = true

-- Copy the complete "doc" folder.
t:install('doc/', '${build_doc}/')

-- Register the action for the documentation.
-- It must run after the finalizer with level 75.
-- It must run before the pack action with level 80.
t:register_action('build_documentation', actionDocBuilder, t, '${prj_root}', 78)


return tResult
