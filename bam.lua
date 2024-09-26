----------------------------------------------------------------------------
--
-- BAM Manual : https://matricks.github.io/bam/bam.html
--

-- DEBUGGING:
-- require("LuaPanda").start()


-----------------------------------------------------------------------------
--
-- Setup the Muhkuh build system.
--
local atEnv = require 'mbs'


----------------------------------------------------------------------------------------------------------------------
--
-- Create all environments.
--

-- FIXME: The MBS2 system should read this from a setup file.
atEnv.DEFAULT.atVars.PROJECT_VERSION = { "0", "0", "3" }

------------------------------------------------------------------------------
--
-- Build the artifacts of crypto_base, test_crypto_personalisation,
--

-- FIXME: The MBS2 system should read the group and module from a setup file.
-- FIXME: An environment should have something like "PROJECT_VERSION_PRETTY"
--        with a string representation of the project version.
local atArtifacts =
{
  strRepositoryPath = 'targets/jonchki/repository',

  {
    strGroup = 'org.muhkuh.tools',
    strModule = 'muhkuh_tester_asciidoc',
    strArtifact = 'muhkuh_tester_asciidoc',
    strProject_version = table.concat(atEnv.DEFAULT.atVars.PROJECT_VERSION,'.'),
    archive = {
      structure = {
        ['doc'] = {
          'doc/main.mustache.asciidoc',
          'doc/missing_test_description.mustache.asciidoc'
        },
        'installer/install.lua'
      },
      extensions = {'tar', 'xz'},
      format = 'tar',
      filter = {'xz'}
    },
    templates = {
      artifact_configuration = 'installer/muhkuh_tester_asciidoc.xml',
      pom = 'installer/pom.xml'
    },
    tHash_ID = {'md5','sha1','sha224','sha256','sha384','sha512'}
  }
}


-----------------------------------------------------------------------------
-- FIXME: Create a builder from the code below.

-- FIXME: Changing the POM template does not trigger a rebuild of the output file.
-- FIXME: Changing the XML template does not trigger a rebuild of the output file.
-- FIXME: The POM file does not need a template file. It can be generated completely in the builder.

local strHash_template = '${ID_UC}:${HASH}\n' -- the builder hash use given Replacements!
local strRepositoryPath = atArtifacts.strRepositoryPath

local atGeneratedFiles = {}

local path = require 'pl.path'
local stringx = require 'pl.stringx'
for _, tArtifactCfg in ipairs(atArtifacts) do
  -- Get the artifact ID and version.
  local strArtifact = tArtifactCfg.strArtifact
  local strProjectVersion = tArtifactCfg.strProject_version
  -- Get the list of hash IDs to generate.
  local tHashIDs = tArtifactCfg.tHash_ID

  -- Get the group as a path.
  local strGroupPath = path.join(
    table.unpack(
      stringx.split(tArtifactCfg.strGroup,'.')
    )
  )
  -- Build the output path for all files.
  local strArtifactPath = path.join(
    strRepositoryPath,
    strGroupPath,
    tArtifactCfg.strModule,
    tArtifactCfg.strProject_version
  )

  -- Get a shortcut to the archive settings.
  local tArchiveCfg = tArtifactCfg.archive

  -- Build the archive
  local strArchiveOutputPath = path.join(
    strArtifactPath,
    string.format(
      '%s-%s',
      strArtifact,
      strProjectVersion
    ) .. '.' .. table.concat(tArchiveCfg.extensions,'.')
  )
  local tArtifact = atEnv.DEFAULT:Archive(
    strArchiveOutputPath,
    tArchiveCfg.format,
    tArchiveCfg.filter,
    tArchiveCfg.structure
  )
  table.insert(atGeneratedFiles, tArtifact)

  -- Build hash of archive
  local tArtifactHash = atEnv.DEFAULT:Hash(
    string.format('%s.hash', tArtifact),
    tArtifact,
    tHashIDs,
    strHash_template
  )
  table.insert(atGeneratedFiles, tArtifactHash)

  local strConfigurationOutputPath = path.join(
    strArtifactPath,
    string.format(
      '%s-%s.xml',
      strArtifact,
      strProjectVersion
    )
  )
  local tConfiguration = atEnv.DEFAULT:VersionTemplate(
    strConfigurationOutputPath,
    tArtifactCfg.templates.artifact_configuration
  )
  table.insert(atGeneratedFiles, tConfiguration)

  local tConfigurationHash = atEnv.DEFAULT:Hash(
    string.format('%s.hash', tConfiguration),
    tConfiguration,
    tHashIDs,
    strHash_template
  )
  table.insert(atGeneratedFiles, tConfigurationHash)

  local strPomOutputPath = path.join(
    strArtifactPath,
    string.format(
      '%s-%s.pom',
      strArtifact,
      strProjectVersion
    )
  )
  local tArtifactPom = atEnv.DEFAULT:VersionTemplate(
    strPomOutputPath,
    tArtifactCfg.templates.pom
  )
  table.insert(atGeneratedFiles, tArtifactPom)
end
