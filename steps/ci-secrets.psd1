# The organization secrets that only CI uses, by the jobs that take them.
# steps/export-secrets.ps1 exports them, apart from those under Data and Cache, and the
# tests check the names against these lists. A secret that only CI uses has no _51DEGREES_ prefix, and its
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

    # Only the steps that download the data files, which set it as
    # _51DEGREES_LICENSE_KEY. The export never takes these names, so no job
    # carries them in its environment.
    Data = @(
        'LICENSE_KEY_V4TAC_IPIV4ENTERPRISE'
    )

    # Only the steps that encrypt the assets before the asset cache is saved
    # and decrypt them after it is restored, with steps/asset-cache.ps1. The
    # export never takes these names, so no job, and no script of the calling
    # repository, carries them in its environment. In the asset prefetch the
    # encrypting step follows the step that runs the repository's
    # ci/fetch-assets.ps1 in the same job, so in a pull request's own run that
    # step follows the pull request's script.
    Cache = @(
        'CACHE_ENCRYPTION_KEY'
    )
}
