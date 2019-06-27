require_relative 'run'
require 'time'
require 'fileutils'

scriptsDir = __dir__
rootDir = File.expand_path(File.join(scriptsDir, ".."))
targetProjectDir = File.join(rootDir, "DeepTarget")
deepDiveRunnerDir = File.join(rootDir, "DeepDiveRunner")
fridaLibraryDir = File.join(rootDir, "CFrida/macos-x86_64")
derivedDir = File.join(rootDir, "derived")

fridaDirectory = "/tmp/frida-latest"
timestampFile = File.join(fridaLibraryDir, "cachedTimestamp")

tmpDir = "/tmp"
testOutputDir = File.join(tmpDir, "XCTestOutput/Test.xcresult")
if Dir.exist?(testOutputDir)
  FileUtils.rm_r(testOutputDir)
end
deployDir = tmpDir

if onCiServer()
  deployDir = ENV['BITRISE_DEPLOY_DIR']
end

htmlFile = File.join(deployDir, "xcode-test-results-Frida.html")
testLogOutput = File.join(tmpDir, "raw-xcodebuild-output.log")

# Update Frida every 24 hoours
if File.exist?(timestampFile)
  timestamp = File.read(timestampFile)
  secondsElapsed = Time.now - Time.parse(timestamp)
  oneDay = 3600 * 24
  if secondsElapsed > oneDay
    if onCiServer()
      FileUtils.rm_rf(fridaDirectory)
    end
    FileUtils.rm(timestampFile)
  end
elsif File.directory?(fridaDirectory)
  if onCiServer()
    FileUtils.rm_rf(fridaDirectory)
  end
end

if File.exist?(timestampFile) == false
  if onCiServer()
    run "git clone --depth 1 --recurse-submodules -j8 --single-branch https://github.com/frida/frida.git #{fridaDirectory}"
  end

  codesignIdentities = run("security find-identity")[:output]
  codesignIdentity = "ci-cert"
  if codesignIdentities.include?(codesignIdentity) == false
    puts "Creating codesign identity"
    createCodesignIdentityScript = File.join(scriptsDir, "createCodesignIdentity.sh")
    run(createCodesignIdentityScript)
  else
    puts "Codesign identity exists"
  end

  Dir.chdir(fridaDirectory) do
    run("git tag -a '99.9.9' -m 'build tag'", failable: true)

    run "echo '' >> frida-core/lib/agent/agent-glue.c"
    ENV["MAC_CERTID"] = codesignIdentity

    run "make -j8 core-macos-thin"
    run "./releng/devkit.py --thin frida-core macos-x86_64 '#{fridaLibraryDir}'"
    time = Time.now.getutc
    File.open(timestampFile, "w") { |file| file.puts "#{time}"}
  end
end

Dir.chdir(rootDir) do
  run "env NSUnbufferedIO=YES COMPILER_INDEX_STORE_ENABLE=NO xcodebuild -scheme Frida -configuration Debug -derivedDataPath \"#{derivedDir}\" build-for-testing"
  result = run("set -o pipefail && env NSUnbufferedIO=YES COMPILER_INDEX_STORE_ENABLE=NO xcodebuild -scheme Frida -configuration Debug -derivedDataPath \"#{derivedDir}\" -resultBundlePath \"#{testOutputDir}\" test-without-building | xcpretty --color --report html --output \"#{htmlFile}\"", failable: true)
  File.open(testLogOutput, "w") { |file| file.puts result[:output]}

  if result[:exitStatus] == 0
    setEnv("BITRISE_XCODE_TEST_RESULT", "succeeded")
  else
    setEnv("BITRISE_XCODE_TEST_RESULT", "failed")
    exit(result[:exitStatus])
  end
end
