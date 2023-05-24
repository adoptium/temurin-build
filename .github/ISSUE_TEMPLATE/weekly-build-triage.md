---
name: 🩺 Weekly Build Triage
about: For triaging the nightly and weekend build failures
title: 'Weekly build triage for the week starting <YYYY>/<MM>/<DD>'
iconName: stethoscope
labels: 'weekly-build-triage'
---

**This week's build triage summary:**

| Date       | Day     | JDK Version | Pipeline | Pass/Build Fail/Test Fail | Triage Status            | Triager | Breakdown    |
| ---------- | ------- | ----------- | -------- | ------------------------- | ------------------------ | ------- | ------------ |
| 2023/03/31 | E.G.day | JDKnn       | Link     | 50/3/19                   | Pending/In Progress/Done | Grogu   | Comment Link |

Note: "Test Fail" is for when all the "build" jobs passed (build, sign, installer, etc) but one of the test jobs failed and the
      status propagated upstream to the build job. Note that "unstable" test job status can be considered a pass, as these are 
      triaged in more detail elsewhere (e.g. the adoptium/aqa-tests repo).


**Comment template:**

Triage breakdown for \<Pipeline link\>

Table of failures:

\| Build Fail\/Test Fail \| Platform   \| Failed Job \| Response                            \| Issue \| Triage Status              \| Notes  \| <br/>
\| --------------------- \| ---------- \| ---------- \| ----------------------------------- \| ----- \| -------------------------- \| -----  \| <br/>
\| Build Fail\/Test Fail \| e.g. win64 \| Link       \| New (Issue)/Existing (Issue)/Ignore \| Link  \| Pending\/In Progress\/Done \| Borked \|