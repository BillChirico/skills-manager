PROJECT := SkillsManager.xcodeproj
SCHEME := SkillsManager
DESTINATION := platform=macOS
DMG_OUTPUT ?= build/release/SkillsManager-unsigned.dmg

.PHONY: generate lint test build app-test packaging-test dmg verify-dmg check

generate:
	@command -v xcodegen >/dev/null || (echo "error: install XcodeGen with 'brew install xcodegen'" && exit 1)
	xcodegen generate --spec project.yml

lint:
	swift format lint \
		--configuration .swift-format \
		--strict \
		--parallel \
		--recursive \
		SkillsManager \
		Packages/SkillsCore/Sources \
		Packages/SkillsCore/Tests \
		Tests

test:
	swift test --package-path Packages/SkillsCore

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		build

app-test:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		test

packaging-test:
	bash Tests/PackagingTests/unsigned-dmg.test.sh

dmg:
	bash scripts/build-unsigned-dmg.sh "$(DMG_OUTPUT)"

verify-dmg:
	bash scripts/verify-unsigned-dmg.sh "$(DMG_OUTPUT)"

check: generate lint test packaging-test
	git diff --exit-code -- $(PROJECT)
	$(MAKE) app-test
