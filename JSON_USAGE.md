# JSON Export Usage Guide

The `mobile-wheels-checker` tool automatically exports JSON alongside markdown reports. This guide shows how to use the JSON data for various purposes.

## JSON Structure

### Full Report (`mobile-wheels-results.json`)

```json
{
  "metadata": {
    "generated": "2025-11-21 10:46:41",
    "packagesChecked": 1500,
    "dependencyChecking": false
  },
  "packages": [
    {
      "name": "numpy",
      "android": "not_available",
      "ios": "supported",
      "iosVersion": "2.3.4",
      "source": "pyswift",
      "category": "pyswift_binary",
      "dependencies": null,
      "allDepsSupported": null
    }
  ],
  "summary": {
    "officialBinaryWheels": 7,
    "pyswiftBinaryWheels": 19,
    "purePython": 1268,
    "binaryWithoutMobile": 166,
    "androidSupport": 6,
    "iosSupport": 24,
    "bothPlatforms": 4,
    "allDepsSupported": null,
    "someDepsUnsupported": null
  }
}
```

### Fields

**Metadata:**
- `generated` - ISO timestamp of report generation
- `packagesChecked` - Total number of packages analyzed
- `dependencyChecking` - Whether dependency analysis was enabled

**Package:**
- `name` - Package name (normalized)
- `android` - Android support: `"supported"`, `"pure_python"`, `"not_available"`, or `"unknown"`
- `androidVersion` - Version number if binary wheels exist (optional)
- `ios` - iOS support: `"supported"`, `"pure_python"`, `"not_available"`, or `"unknown"`
- `iosVersion` - Version number if binary wheels exist (optional)
- `source` - Package source: `"pypi"` or `"pyswift"`
- `category` - Package category: `"official_binary"`, `"pyswift_binary"`, `"pure_python"`, or `"binary_without_mobile"`
- `dependencies` - Array of dependency package names (only if `--deps` flag was used)
- `allDepsSupported` - Boolean indicating if all dependencies are supported (only if `--deps` flag was used)

**Summary:**
- Package counts by category
- Platform support statistics
- Dependency statistics (if enabled)

### Chunked JSON (for >1000 packages)

**Index file (`json-chunks/index.json`):**
```json
{
  "total_packages": 1460,
  "chunk_size": 1000,
  "total_chunks": 2,
  "chunks": [
    {
      "filename": "chunk-1.json",
      "start_index": 0,
      "end_index": 999,
      "count": 1000
    },
    {
      "filename": "chunk-2.json",
      "start_index": 1000,
      "end_index": 1459,
      "count": 460
    }
  ]
}
```

**Chunk files (`chunk-N.json`):**
Each chunk contains an array of package objects (same structure as the full report).

## Use Cases

### 1. Simple Client-Side Search (MkDocs + JavaScript)

Create a search page in your MkDocs site:

**docs/search.md:**
```markdown
# Package Search

<input type="text" id="search-input" placeholder="Search packages..." />
<div id="results"></div>

<script src="js/package-search.js"></script>
```

**docs/js/package-search.js:**
```javascript
let packagesData = [];

// Load JSON data
fetch('mobile-wheels-results.json')
  .then(response => response.json())
  .then(data => {
    packagesData = data.packages;
    console.log(`Loaded ${packagesData.length} packages`);
  });

// Search functionality
document.getElementById('search-input').addEventListener('input', (e) => {
  const query = e.target.value.toLowerCase();
  const results = packagesData.filter(pkg => 
    pkg.name.toLowerCase().includes(query)
  ).slice(0, 50); // Limit to 50 results
  
  displayResults(results);
});

function displayResults(results) {
  const container = document.getElementById('results');
  
  if (results.length === 0) {
    container.innerHTML = '<p>No packages found</p>';
    return;
  }
  
  const html = results.map(pkg => `
    <div class="package-result">
      <h3>${pkg.name}</h3>
      <p>
        <strong>Android:</strong> ${formatSupport(pkg.android)} 
        ${pkg.androidVersion ? `(${pkg.androidVersion})` : ''}
        <br>
        <strong>iOS:</strong> ${formatSupport(pkg.ios)} 
        ${pkg.iosVersion ? `(${pkg.iosVersion})` : ''}
        <br>
        <strong>Category:</strong> ${pkg.category.replace(/_/g, ' ')}
        <br>
        <strong>Source:</strong> ${pkg.source}
      </p>
    </div>
  `).join('');
  
  container.innerHTML = html;
}

function formatSupport(status) {
  const icons = {
    'supported': '✅ Supported',
    'pure_python': '🐍 Pure Python',
    'not_available': '⚠️ Not Available',
    'unknown': '❓ Unknown'
  };
  return icons[status] || status;
}
```

### 2. Lazy Loading with Chunked JSON

For large datasets, load chunks on-demand:

```javascript
let chunkIndex = null;
let loadedChunks = {};

// Load chunk index first
async function initialize() {
  const response = await fetch('json-chunks/index.json');
  chunkIndex = await response.json();
  console.log(`Total packages: ${chunkIndex.total_packages}, Chunks: ${chunkIndex.total_chunks}`);
}

// Load specific chunk
async function loadChunk(chunkNumber) {
  if (loadedChunks[chunkNumber]) {
    return loadedChunks[chunkNumber];
  }
  
  const filename = `json-chunks/chunk-${chunkNumber}.json`;
  const response = await fetch(filename);
  const data = await response.json();
  
  loadedChunks[chunkNumber] = data;
  return data;
}

// Search across all chunks
async function searchAllPackages(query) {
  await initialize();
  
  let allResults = [];
  
  for (let i = 1; i <= chunkIndex.total_chunks; i++) {
    const chunk = await loadChunk(i);
    const results = chunk.filter(pkg => 
      pkg.name.toLowerCase().includes(query.toLowerCase())
    );
    allResults.push(...results);
  }
  
  return allResults;
}
```

### 3. Database Import (PostgreSQL)

Create a table and import JSON:

```sql
-- Create table
CREATE TABLE python_packages (
    name VARCHAR(255) PRIMARY KEY,
    android_support VARCHAR(50),
    android_version VARCHAR(50),
    ios_support VARCHAR(50),
    ios_version VARCHAR(50),
    source VARCHAR(50),
    category VARCHAR(50),
    dependencies TEXT[],
    all_deps_supported BOOLEAN
);

-- Import JSON (using Python)
```

**import_to_postgres.py:**
```python
import json
import psycopg2

# Load JSON
with open('mobile-wheels-results.json', 'r') as f:
    data = json.load(f)

# Connect to database
conn = psycopg2.connect(
    dbname="mobile_packages",
    user="your_user",
    password="your_password",
    host="localhost"
)
cur = conn.cursor()

# Insert packages
for pkg in data['packages']:
    cur.execute("""
        INSERT INTO python_packages 
        (name, android_support, android_version, ios_support, ios_version, 
         source, category, dependencies, all_deps_supported)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (name) DO UPDATE SET
            android_support = EXCLUDED.android_support,
            ios_support = EXCLUDED.ios_support
    """, (
        pkg['name'],
        pkg['android'],
        pkg.get('androidVersion'),
        pkg['ios'],
        pkg.get('iosVersion'),
        pkg['source'],
        pkg['category'],
        pkg.get('dependencies'),
        pkg.get('allDepsSupported')
    ))

conn.commit()
cur.close()
conn.close()

print(f"Imported {len(data['packages'])} packages")
```

### 4. SQLite WASM (Client-Side Database)

Use SQL.js for client-side database:

```html
<!DOCTYPE html>
<html>
<head>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/sql-wasm.js"></script>
</head>
<body>
    <input type="text" id="search" placeholder="Search packages..." />
    <div id="results"></div>

    <script>
    let db;

    // Initialize database
    async function initDB() {
        const SQL = await initSqlJs({
            locateFile: file => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/${file}`
        });
        
        db = new SQL.Database();
        
        // Create table
        db.run(`
            CREATE TABLE packages (
                name TEXT PRIMARY KEY,
                android TEXT,
                ios TEXT,
                category TEXT,
                source TEXT
            )
        `);
        
        // Load and insert data
        const response = await fetch('mobile-wheels-results.json');
        const data = await response.json();
        
        const stmt = db.prepare(`
            INSERT INTO packages (name, android, ios, category, source)
            VALUES (?, ?, ?, ?, ?)
        `);
        
        for (const pkg of data.packages) {
            stmt.run([pkg.name, pkg.android, pkg.ios, pkg.category, pkg.source]);
        }
        
        stmt.free();
        console.log('Database ready!');
    }

    // Search function
    function search(query) {
        const results = db.exec(`
            SELECT * FROM packages 
            WHERE name LIKE '%${query}%'
            LIMIT 50
        `);
        
        return results[0]?.values || [];
    }

    // Initialize on page load
    initDB();

    // Search event
    document.getElementById('search').addEventListener('input', (e) => {
        const results = search(e.target.value);
        displayResults(results);
    });
    </script>
</body>
</html>
```

### 5. MkDocs Integration with Material Theme

Add custom search page to `mkdocs.yml`:

```yaml
site_name: Python Mobile Packages
theme:
  name: material
  features:
    - navigation.instant
    - search.suggest

extra_css:
  - css/custom.css

extra_javascript:
  - js/package-search.js

nav:
  - Home: index.md
  - Package Search: search.md
  - Reports: mobile-wheels-results.md

# Copy JSON files to docs
extra:
  files:
    - mobile-wheels-results.json
    - json-chunks/
```

### 6. Static Site Generator (11ty Example)

Use JSON as data source for 11ty:

**_data/packages.js:**
```javascript
const fs = require('fs');

module.exports = () => {
  const data = JSON.parse(fs.readFileSync('./mobile-wheels-results.json'));
  return data.packages;
};
```

**packages.njk:**
```html
---
pagination:
  data: packages
  size: 20
layout: base.njk
---

<h1>Python Packages for Mobile</h1>

{% for package in pagination.items %}
<div class="package">
  <h2>{{ package.name }}</h2>
  <p>Android: {{ package.android }}</p>
  <p>iOS: {{ package.ios }}</p>
  <p>Category: {{ package.category }}</p>
</div>
{% endfor %}

<nav>
  {% if pagination.previousPageHref %}<a href="{{ pagination.previousPageHref }}">Previous</a>{% endif %}
  {% if pagination.nextPageHref %}<a href="{{ pagination.nextPageHref }}">Next</a>{% endif %}
</nav>
```

## Performance Tips

1. **For < 1000 packages**: Load full JSON directly
2. **For > 1000 packages**: Use chunked JSON with lazy loading
3. **For search**: Consider Lunr.js or Fuse.js for better search
4. **For filtering**: Use database (SQLite WASM, IndexedDB, or server-side)
5. **For production**: Enable gzip compression on JSON files

## Advanced: Lunr.js Integration

```javascript
// Build search index
async function buildSearchIndex() {
  const response = await fetch('mobile-wheels-results.json');
  const data = await response.json();
  
  const idx = lunr(function() {
    this.ref('name');
    this.field('name', { boost: 10 });
    this.field('category');
    
    data.packages.forEach(pkg => {
      this.add(pkg);
    });
  });
  
  return { idx, packages: data.packages };
}

// Search with Lunr
async function search(query) {
  const { idx, packages } = await buildSearchIndex();
  const results = idx.search(query);
  
  return results.map(result => 
    packages.find(pkg => pkg.name === result.ref)
  );
}
```

## See Also

- [README.md](README.md) - Main documentation
- [EXAMPLES.md](EXAMPLES.md) - Swift library usage examples
- [MkDocs Documentation](https://www.mkdocs.org/)
- [Lunr.js](https://lunrjs.com/) - Client-side search library
- [SQL.js](https://github.com/sql-js/sql.js/) - SQLite in the browser
