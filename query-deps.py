import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent / ".build/checkouts/realm-swift/RealmSwift"))

import realm

config = realm.Configuration(str(Path("test-deps-sample.realm")))
realm_db = realm.Realm(config)

# Query packages with dependencies
packages_with_deps = realm_db.objects("PackageResult").filter("dependencies.@count > 0")

print(f"Total packages: {realm_db.objects('PackageResult').count()}")
print(f"Packages with dependencies: {packages_with_deps.count()}")
print("\nSample packages with dependencies:")

for i, pkg in enumerate(packages_with_deps[:10]):
    print(f"\n{i+1}. {pkg.name}")
    print(f"   Dependencies: {pkg.dependencies.count()}")
    for dep in list(pkg.dependencies)[:3]:
        print(f"     - {dep.name}: Android={dep.androidSupport}, iOS={dep.iosSupport}")
