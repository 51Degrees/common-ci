# The organization secrets that only CI uses, by the jobs that take them.
# steps/export-secrets.ps1 exports them and the tests check the names against
# these lists. A secret that only CI uses has no _51DEGREES_ prefix, and its
# name says what it does.
@{
    # Every job that exports its secrets.
    Every = @(
        'CI_ACCESS_TOKEN'
    )

    # Only a job that publishes.
    Publish = @(
        'PUBLISH_ACCESS_TOKEN'
        'NUGET_API_KEY'
        'NPM_AUTH_TOKEN'
        'PYPI_TOKEN'
        'MAVEN_SETTINGS'
    )

    # Only a job that signs.
    Sign = @(
        'CODE_SIGNING_KEY_VAULT_CERTIFICATE_DATA'
        'CODE_SIGNING_KEY_VAULT_CERTIFICATE_NAME'
        'CODE_SIGNING_KEY_VAULT_CLIENT_ID'
        'CODE_SIGNING_KEY_VAULT_CLIENT_SECRET'
        'CODE_SIGNING_KEY_VAULT_NAME'
        'CODE_SIGNING_KEY_VAULT_TENANT_ID'
        'CODE_SIGNING_KEY_VAULT_URL'
        'JAVA_GPG_KEY_PASSPHRASE'
        'JAVA_KEY_PGP_FILE'
        'STRONG_NAME_KEY_BASE64'
    )
}
