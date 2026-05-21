// Cloud Functions entry point. Each trigger lives in its own file under
// `triggers/`; re-export them here so Firebase discovers each one as a
// deployable function. The shape of the schema each handler observes is
// documented in `docs/superpowers/specs/2026-05-21-notifications-design.md`.

import {initializeApp} from "firebase-admin/app";

initializeApp();

export {onVoterWritten} from "./triggers/vote";
export {onProblemForked} from "./triggers/fork";
export {onProblemLinkedWritten} from "./triggers/link";
export {onRevisionCreated} from "./triggers/revision";
