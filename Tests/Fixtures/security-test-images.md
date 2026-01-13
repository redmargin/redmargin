# Security Test: Image Loading

## Local Image - Relative Path (SHOULD WORK)

![Relative path](test-image.jpg)

## Local Image - Absolute Path (SHOULD WORK)

![Absolute path](/Users/marco/dev/redmargin/Tests/Fixtures/test-image.jpg)

## Base64 PNG Data URI (SHOULD WORK)

![Base64 red square](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMgAAADICAIAAAAiOjnJAAABcklEQVR42u3SMQ0AAAjAsPk3DSY4OJpUwbKm4JwEGAtjYSwwFsbCWGAsjIWxwFgYC2OBsTAWxgJjYSyMBcbCWBgLjIWxMBYYC2NhLDAWxsJYYCyMhbHAWBgLY4GxMBbGAmNhLIwFxsJYGAuMhbEwFhgLY2EsMBbGwlhgLIyFscBYGAtjgbEwFsYCY2EsjAXGwlgYC4yFsTAWGAtjYSwwFsbCWGAsjIWxwFgYC2OBBBgLY2EsMBbGwlhgLIyFscBYGAtjgbEwFsYCY2EsjAXGwlgYC4yFsTAWGAtjYSwwFsbCWGAsjIWxwFgYC2OBsTAWxgJjYSyMBcbCWBgLjIWxMBYYC2NhLDAWxsJYYCyMhbHAWBgLY4GxMBbGAmNhLIwFxsJYGAuMhbEwFhgLY2EsMBbGwlhgLIyFscBYGAtjgbEwFsbCWBJgLIyFscBYGAtjgbEwFsYCY2EsjAXGwlgYC4yFsTAWGAtjYSwwFsbCWGAs3lnRh6zWL0rapgAAAABJRU5ErkJggg==)

## SVG Data URI (SHOULD BE BLOCKED - can contain scripts)

![SVG blocked](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIiBmaWxsPSJyZWQiLz48L3N2Zz4=)

## Remote Image (SHOULD BE BLOCKED)

![Remote image](https://httpbin.org/image/png)
