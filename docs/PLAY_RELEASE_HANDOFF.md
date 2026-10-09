# Perspective Opus Play release

Complete the existing Google Play submission for Perspective Opus. The user has authorized finishing the release and setting its download price to US$1.99. They questioned the earlier 13+ audience choice. The prepared audience includes children aged 6-12 and older players.

Use a working computer-use browser signed in as `randy@randroid.dev` at https://play.google.com/console. Select the Toyboxes organization, developer ID `4940278051196101377`, and the existing Perspective Opus app, app ID `4974223691200858640`, package `app.toyboxes.perspectiveopus`. Verify these identifiers before editing. Do not create a duplicate app.

The release files are in the attached `PerspectiveOpus-1.1.0-code2-play-release.zip`, or in `/Users/randroid/Documents/Dev/PerspectiveOpusAndroid/build/play-release-1.1.0-code2/` on the original Mac. Extract the ZIP before uploading individual files. If the agent runs on another computer, use the attached ZIP rather than assuming the Mac path exists.

## Apply pricing first

Open Products > App pricing. Change the unpublished draft from Free to Paid and save a US price of exactly USD 1.99. Use Play's local conversion and tax handling for other supported countries. Read the US price back after saving, and verify the app is marked Paid before publishing any track.

If Play refuses the change because this package was already offered for free, report that exact blocker. Do not release it for free or create a replacement package. If a missing payments profile requires personal banking or tax information, let the user enter it directly in Console, then continue. Do not invent financial information.

## Update audience and declarations

Open Policy > App content > Target audience and content. Select ages 6-8, 9-12, 13-15, 16-17, and 18 and over, including both children and older players. Do not select ages 5 and under: the game uses timed platform jumps, spatial puzzles, and written menu labels. These audience groups describe the intended players, not a replacement content rating.

Complete the resulting Families questions truthfully using `policy-answers.md`: no ads or ad SDKs, no sign-in, no analytics, no data collected or shared, no in-app purchases, no social features, and no AR. The app is offline; progress and settings stay on the device. All features are accessible after downloading the paid app, with no additional purchases.

Keep the existing IARC answers and results: ESRB Everyone with Mild Fantasy Violence, PEGI 3, USK 6+, and IARC 3+. The cartoon hazards splash Quaver into ink and return him to a checkpoint. Keep the privacy policy at https://perspective-opus.vercel.app/privacy.html, support email `support@toyboxes.app`, category Game > Puzzle, and website https://perspective-opus.vercel.app. Review and save the summary of each changed declaration.

## Finish the listing

In the English (US) default listing, use the exact app name, short description, and full description in `listing/`. The updated description says no in-app purchases; it does not claim that the Android download is free.

Keep or upload `graphics/icon-512.png` and `graphics/feature.png`. Upload the four screenshots in filename order from `graphics/phone-01-*.png` through `phone-04-*.png`. Use their alt text from `screenshots.json` if the Console offers alt-text fields. These are unedited captures of the actual native game with touch controls at 1920x1080. They were rendered on the Mac using the Mobile renderer, not captured on the Pixel. Save the listing and verify all four previews appear in the expected order.

## Upload and submit

Upload `PerspectiveOpus.aab`, version 1.1.0, version code 2. Its SHA-256 is `d2359a7d6fc700f1fd89fc4b273a6b03a7396f7e824b95efad7e506b688ab86a`. Use the AAB, not an APK or the self-test package. Preserve the package ID and existing upload key. Do not request, upload, or expose private keystore files or passwords.

Finish the ordinary Play App Signing setup if this first bundle requires it. Wait for bundle processing and inspect every reported issue. A non-blocking warning may be documented; any error that requires a different binary must be reported rather than bypassed. Do not substitute an older bundle or change the version number without a rebuilt artifact.

An internal testing release can be used to validate the bundle first, with `randy@randroid.dev` as the tester. Do not add or message other testers. The requested endpoint is a paid production release submitted for Google review. Promote the same validated bundle to Production or upload it there directly if internal staging is unnecessary. Use `release-notes/en-US.txt`, make it available in the supported priced countries, and complete the first-release rollout and Publishing overview submission. No further permission is required to submit this authorized paid release for review.

## Verify and report

Read back the saved US$1.99 paid price, selected audience groups, version 1.1.0/code 2, gallery previews, and release track. Capture the final Publishing overview and release state. Report the actual status, such as draft, changes in review, approved but awaiting publication, or live. Do not claim it is live merely because the upload completed or the review submission succeeded. Include the Console app/release URL and, when available, the public Play URL or internal opt-in link. If blocked, report the exact screen, message, and remaining action.

## Prepared evidence and current limit

The signed APK and AAB match the release receipt. The Pixel completed all six movements with 42 notes and zero deaths before the final renderer preparation change. After that change, the updated phone flow passed 42 checks and the regular release passed OS-level touch switching and Android back handling. A non-silent stereo playback capture has no clipped samples. A longer updated full-campaign phone benchmark and physical speaker listening are not claimed.

The current publishing attempt could navigate to Console but could not inspect it: both snapshot and DOM evaluation timed out after 15 seconds, including a fresh tab. No new Console edits or uploads were made. Files and requested settings are ready; the handoff agent must verify the live Console state before applying them.

Policy references checked 9 October 2026:

- [App pricing](https://support.google.com/googleplay/android-developer/answer/6334373?hl=en)
- [Target audience guidance](https://support.google.com/googleplay/android-developer/answer/9867159?hl=en)
- [Families requirements](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en)
- [Preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
