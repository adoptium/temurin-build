---
name: 🩺 Weekly Build Triage
about: For triaging the nightly and weekend build failures
title: 'Weekly build triage for the week starting Saturday <YYYY>/<MM>/<DD>'
iconName: stethoscope
labels: 'weekly-build-triage'
---

**This week's build triage summary:**

| Date       | Day     | JDK Version | Pipeline | Pass/Build Fail/Test Fail | Pass/Preventable/Unpreventable |
| ---------- | ------- | ----------- | -------- | ------------------------- | ------------------------------ |
| 2023/03/31 | E.G.day | JDKnn       | Link     | 1/2/345                   | 6/7/8910                       |

Note: "Test Fail" is for when all the "build" jobs passed (build, sign, installer, etc) but one of the test jobs failed and the
      status propagated upstream to the build job. Note that "unstable" test job status can be considered a pass, as these are 
      triaged in more detail [here](www.github.com/adoptium/aqa-tests).


**Comment template:**

Triage breakdown for \<Weekday\>

List of failures:

\<link to failing job\>
\<Problem summary\>
New/Existing Issue: \<Issue link\>
Preventable: Yes/No

Repeat as needed.