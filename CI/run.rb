#!/usr/bin/ruby

STDOUT.sync = true

require 'open3'

def run(command, failable: false)
	puts command
	output = ""
	exitStatus = 0

	Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
		while line = stdout_err.gets
			puts line
			output += line
			STDOUT.flush
		end

		exitStatus = wait_thr.value.exitstatus
		if exitStatus != 0
			puts "Command failed: #{command}"
			if failable == false
				exit(exitStatus)
			end # failable
		end
	end # popen2e

	return {output: output, exitStatus: exitStatus}
end

def onCiServer()
	return ENV['BITRISE_SOURCE_DIR'] != nil
end


def setEnv(key, value)
	if onCiServer() == false
		return
	end
	ENV[key] = value
  run "envman add --key \"#{key}\" --value \"#{value}\""
end
