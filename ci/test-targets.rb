# Цели тестов поверх project.yml — сам project.yml не меняется (этапы A и I). Пишет audit-project.yml:
#   AlbakovAudit — UI-тесты (папка audit/), AlbakovUnit — юнит-тесты (audit-unit/), схема AlbakovAudit с обеими.
# Один механизм на оба workflow: audit.yml (полный аудит с копией магазина) и ios.yml (юнит-тесты при каждой сборке).
# Запуск: ruby ci/test-targets.rb && xcodegen generate --spec audit-project.yml
require "yaml"

s = YAML.load_file("project.yml")
s["targets"]["AlbakovAudit"] = {
  "type" => "bundle.ui-testing", "platform" => "iOS",
  "sources" => [{ "path" => "audit" }],
  "dependencies" => [{ "target" => "Albakov" }],
  "settings" => { "base" => { "PRODUCT_BUNDLE_IDENTIFIER" => "ru.albakovofficial.audit", "GENERATE_INFOPLIST_FILE" => "YES",
                              "TEST_TARGET_NAME" => "Albakov", "SWIFT_VERSION" => "5.0" } } }
s["targets"]["AlbakovUnit"] = {
  "type" => "bundle.unit-test", "platform" => "iOS",
  "sources" => [{ "path" => "audit-unit" }],
  "dependencies" => [{ "target" => "Albakov" }],
  "settings" => { "base" => { "PRODUCT_BUNDLE_IDENTIFIER" => "ru.albakovofficial.unit", "GENERATE_INFOPLIST_FILE" => "YES",
                              "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/Albakov.app/Albakov", "BUNDLE_LOADER" => "$(TEST_HOST)",
                              "SWIFT_VERSION" => "5.0" } } }
s["schemes"] = { "AlbakovAudit" => { "build" => { "targets" => { "Albakov" => "all", "AlbakovAudit" => ["test"], "AlbakovUnit" => ["test"] } },
                                     "test" => { "config" => "Debug", "targets" => ["AlbakovUnit", "AlbakovAudit"] } } }
File.write("audit-project.yml", s.to_yaml)
