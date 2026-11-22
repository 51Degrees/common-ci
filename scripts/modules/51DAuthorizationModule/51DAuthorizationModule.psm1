# Get the path to the script parent folder.
$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition

# Class contains definition of authorization string.
class Authorization {
	static [string]$AuthorizationString = "Bearer $Env:SYSTEM_ACCESSTOKEN"
	# When using this script locally, create a authorization -setting.json with the following content:
	# { "Base64PAT": "Basic [Your Base 64 PAT]" }
	# Update it with your base 64 encoded PAT as described at
	# https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page#use-a-pat
	#
	# Then uncomment the following line, load this module and run 'Using module 51DAuthorizationModule' in a fresh environment if
	# accessing this directly from a terminal.
	# 
	# static [string]$AuthorizationString = $(Get-Content $scriptPath/authorization-settings.json -Raw | Out-String | ConvertFrom-Json).Base64PAT
}