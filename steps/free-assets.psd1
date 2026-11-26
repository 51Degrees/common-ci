# The free data files and test evidence, which come from the data repository,
# https://github.com/51Degrees/data, by asset name and path in that
# repository. steps/fetch-assets.ps1 gets them from there, and
# steps/asset-cache.ps1 saves them to the asset cache as they are. Every
# other asset is encrypted before it is saved.
@{
    '51Degrees-LiteV4.1.hash' = 'device-detection/51Degrees-LiteV4.1.hash'
    '20000 Evidence Records.yml' = 'device-detection/20000 Evidence Records.yml'
    '51Degrees-LiteIpiV41.ipi' = 'ip-intelligence/51Degrees-LiteV41.ipi'
    '51Degrees-IPIV4AsnIpiV41.ipi' = 'ip-intelligence/51Degrees-IPIV4AsnIpiV41.ipi'
    'ip-intelligence-evidence.yml' = 'ip-intelligence/evidence.yml'
}
