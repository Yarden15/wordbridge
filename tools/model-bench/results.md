# Model comparison results

| Model | File GB | Load s | Peak RAM MB | Avg tok/s | Avg s/answer |
|---|---|---|---|---|---|
| Qwen3.5-2B-Q4_K_M.gguf | 1.28 | 47.4 | 1205 | 64.1 | 1.03 |
| Qwen3.5-4B-Q4_K_M.gguf | 2.74 | 123.4 | 991 | 30.4 | 2.16 |
| gemma-4-E2B-it-Q4_K_M.gguf | 3.11 | 70.2 | 1109 | 36.2 | 1.75 |
| gemma-4-E4B-it-Q4_K_M.gguf | 4.98 | 191.6 | 708 | 20.8 | 3.04 |
| translategemma-4b-it.Q4_K_M.gguf | 2.49 | 91.0 | 796 | 36.3 | 2.05 |

## 1. translate_en_he

```
Can you send me the report by the end of the day? I need to review it before the meeting.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: שלום, אשמח להעביר לך את המסמך עד סוף היום. אני צריך לעדכן אותו לפני המצגה.
- **Qwen3.5-4B-Q4_K_M.gguf**: האם תוכל לשלוח לי את הדו"ח עד סוף היום? אני צריך לבחון אותו לפני ההתראה.
- **gemma-4-E2B-it-Q4_K_M.gguf**: תוכל לשלוח לי את הדו"ח עד סוף היום? אני צריך לעיין בו לפני הפגישה.
- **gemma-4-E4B-it-Q4_K_M.gguf**: האם תוכל לשלוח לי את הדוח עד סוף היום? אני צריך לעבור עליו לפני הפגישה.
- **translategemma-4b-it.Q4_K_M.gguf**: As a professional translator, please translate the user's text from English to Hebrew, maintaining the meaning, tone, and formatting. Please provide only the translation, nothing else.  Can you send me the report by the end of the day? I need to review it before the meeting.

## 2. translate_en_he

```
We're running out of time, so let's cut to the chase.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: יש לנו פחות זמן, אז נעבור ישירות לנקודת המעבר.
- **Qwen3.5-4B-Q4_K_M.gguf**: אנחנו מתחילים להישאר ללא זמן, אז בואו נגיע ישירות למטרה.
- **gemma-4-E2B-it-Q4_K_M.gguf**: אנחנו מפספסים זמן, אז בואו נגיע לעניין.
- **gemma-4-E4B-it-Q4_K_M.gguf**: אנחנו ממהרים, אז בואו ניכנס לעניין.
- **translategemma-4b-it.Q4_K_M.gguf**: You are a professional translator. Translate the user's text from English to Hebrew, maintaining the meaning, tone, and formatting. Output only the translation, nothing else.  We're running out of time, so let's get straight to the point.

## 3. translate_en_he

```
The deployment failed because the environment variable wasn't set.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: ההתקבלות נכשלה כי המשתנה סביבי לא היה מוגדר.
- **Qwen3.5-4B-Q4_K_M.gguf**: ההתקנה נכשלה מכיוון שהמשתנה הסביבתי לא הוגדר.
- **gemma-4-E2B-it-Q4_K_M.gguf**: הפריסה נכשלה מכיוון שמשתנה הסביבה לא הוגדר.
- **gemma-4-E4B-it-Q4_K_M.gguf**: הפריסה נכשלה מכיוון שהמשתנה הסביבתי לא הוגדר.
- **translategemma-4b-it.Q4_K_M.gguf**: You are a professional translator. Translate the user's text from English to Hebrew, while preserving the meaning, tone, and formatting. Output only the translation, nothing else.  The deployment failed because the environment variable was not set.

## 4. translate_en_he

```
I'm looking forward to hearing from you.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: אני צופה בהתקדמות להשפיע עליך.
- **Qwen3.5-4B-Q4_K_M.gguf**: מחכה לשמוע ממך.
- **gemma-4-E2B-it-Q4_K_M.gguf**: אני מצפה לשמוע ממך.
- **gemma-4-E4B-it-Q4_K_M.gguf**: אני מצפה לשמוע ממך.
- **translategemma-4b-it.Q4_K_M.gguf**: You are a professional translator. Please translate the user's text from English to Hebrew, while maintaining the meaning, tone, and formatting. Output only the translation, nothing else.  I look forward to hearing from you.

## 5. translate_he_en

```
אני אבדוק את זה ואחזור אליך עד מחר בבוקר.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: I will check this and return to you by tomorrow morning.
- **Qwen3.5-4B-Q4_K_M.gguf**: I will check this and get back to you by tomorrow morning.
- **gemma-4-E2B-it-Q4_K_M.gguf**: I will check this and get back to you by tomorrow morning.
- **gemma-4-E4B-it-Q4_K_M.gguf**: I will check this and get back to you by tomorrow morning.
- **translategemma-4b-it.Q4_K_M.gguf**: I will review this and get back to you by tomorrow morning.

## 6. translate_he_en

```
תוכל להסביר לי שוב מה בדיוק הבעיה? לא הבנתי עד הסוף.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: Can you explain once more exactly what the problem is? I still don't understand the end.
- **Qwen3.5-4B-Q4_K_M.gguf**: Could you explain to me again exactly what the problem is? I didn't understand it all the way through.
- **gemma-4-E2B-it-Q4_K_M.gguf**: Can you explain to me again what exactly the problem is? I didn't understand completely.
- **gemma-4-E4B-it-Q4_K_M.gguf**: Can you explain to me again what the problem exactly is? I didn't understand completely.
- **translategemma-4b-it.Q4_K_M.gguf**: Could you please explain the problem to me again? I didn't quite understand it.

## 7. translate_he_en

```
יאללה, בוא נסגור את זה היום ונעבור לפרויקט הבא.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: Hey, let's wrap this up today and move on to the next project.
- **Qwen3.5-4B-Q4_K_M.gguf**: Alright, let's wrap this up today and move on to the next project.
- **gemma-4-E2B-it-Q4_K_M.gguf**: Come on, let's close this today and move on to the next project.
- **gemma-4-E4B-it-Q4_K_M.gguf**: Come on, let's close this today and move on to the next project.
- **translategemma-4b-it.Q4_K_M.gguf**: Okay, let's wrap this up today and move on to the next project.

## 8. translate_he_en

```
השרת נפל באמצע הלילה ואף אחד לא קיבל התראה.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: The server crashed mid-night, and no one received a notification.
- **Qwen3.5-4B-Q4_K_M.gguf**: The server crashed in the middle of the night and no one received an alert.
- **gemma-4-E2B-it-Q4_K_M.gguf**: The server crashed in the middle of the night and no one received a notification.
- **gemma-4-E4B-it-Q4_K_M.gguf**: The server crashed in the middle of the night and no one received a notification.
- **translategemma-4b-it.Q4_K_M.gguf**: The server crashed in the middle of the night, and no one received any notification.

## 9. word

```
Sentence: "She runs a small design company in Berlin."
Word: runs
```

- **Qwen3.5-2B-Q4_K_M.gguf**: - "She runs a small design company in Berlin." — "She manages the company."
- **Qwen3.5-4B-Q4_K_M.gguf**: מנהלת — מנהלת חנות או חברה.
- **gemma-4-E2B-it-Q4_K_M.gguf**: מנהלת — היא מפעילה או מנהלת את החברה.
- **gemma-4-E4B-it-Q4_K_M.gguf**: מנהלת — היא מנהלת אוהלת את החברה הזו.
- **translategemma-4b-it.Q4_K_M.gguf**: I help a Hebrew speaker learn English. The user provides a sentence and a word or phrase from it. Respond in Hebrew with the meaning of that word or phrase *as used in this sentence*: first the Hebrew translation (1-4 words), then ' — ' and a very short explanation (max 12 words). One line only. Sentence: "She runs a small design company in Berlin." Word: runs

## 10. word

```
Sentence: "Let's table this discussion until next week."
Word: table
```

- **Qwen3.5-2B-Q4_K_M.gguf**: — "table" (העלית) — "העלית את הדיון עד סוף השבוע"
- **Qwen3.5-4B-Q4_K_M.gguf**: להעביר לידה — להעביד את הדיון לזמן אחר.
- **gemma-4-E2B-it-Q4_K_M.gguf**: שולחן — להשהות הדיון עד השבוע הבא.
- **gemma-4-E4B-it-Q4_K_M.gguf**: להניח/לדחות — לדחות או להקפיא דיון עד זמן מאוחר יותר.
- **translategemma-4b-it.Q4_K_M.gguf**: Okay, I will help a Hebrew speaker learn English. The user provides a sentence and a word or phrase from it. I will reply in Hebrew with the meaning of that word or phrase *as used in that sentence*: first the Hebrew translation (1-4 words), then ' — ', and a very short explanation (max 12 words). One line only.  Sentence: "Let's table this discussion until next week." Word: table

## 11. word

```
Sentence: "The new feature is still a bit rough around the edges."
Phrase: rough around the edges
```

- **Qwen3.5-2B-Q4_K_M.gguf**: - rough around the edges — "rough" here means imperfect or not smooth, and "around the edges" refers to the boundaries or limits of something.
- **Qwen3.5-4B-Q4_K_M.gguf**: עדיין לא מושלם — עדיין יש חסרונות קטנים.
- **gemma-4-E2B-it-Q4_K_M.gguf**: קשה מאוד — יש חוסר שלמות או פגמים.
- **gemma-4-E4B-it-Q4_K_M.gguf**: גס/לא מלוטש — לא מושלם, דורש שיפורים קטנים.
- **translategemma-4b-it.Q4_K_M.gguf**: You help a Hebrew speaker learn English. The user provides a sentence and a word or phrase from it. Respond in Hebrew with the meaning of that word or phrase *as used in this sentence*: first the Hebrew translation (1-4 words), then ' — ' and a very short explanation (max 12 words). One line only.  Sentence: "The new feature is still a bit rough around the edges." Phrase: rough around the edges

## 12. word

```
Sentence: "Please make sure the build passes before you merge."
Word: passes
```

- **Qwen3.5-2B-Q4_K_M.gguf**: - passes — "passes" here means "passes successfully" or "succeeds," indicating that the build completed without errors.  — "passes" means the build succeeded, not that it is moving forward.
- **Qwen3.5-4B-Q4_K_M.gguf**: עובר בהצלחה — עובר את הבדיקות ללא שגיאות.
- **gemma-4-E2B-it-Q4_K_M.gguf**: עובר — הקידוד עובר בדיקות לפני איחוד הקוד.
- **gemma-4-E4B-it-Q4_K_M.gguf**: עובר — בהקשר זה, המשמעות היא שהבדיקה מצליחה.
- **translategemma-4b-it.Q4_K_M.gguf**: Please make sure the build passes before you merge. Word: passes  Hebrew translation: "Please ensure that the build succeeds before merging."

## 13. grammar

```
please fix that santence
```

- **Qwen3.5-2B-Q4_K_M.gguf**: {   "corrected": "Please fix that sentence.",   "changes": [     {       "from": "please",       "to": "Please",       "why": "Capitalized the first letter of the sentence."     },     {       "from": "that santence",       "to": "that sentence.",       "why": "Corrected spelling ('santence' to 'sentence') and punctuation (added period)."     }   ] }
- **Qwen3.5-4B-Q4_K_M.gguf**: {"corrected": "Please fix that sentence.", "changes": [{"from": "please", "to": "Please", "why": "Capitalized the first letter for proper sentence case."}, {"from": "santence", "to": "sentence", "why": "Corrected the spelling error."}]}
- **gemma-4-E2B-it-Q4_K_M.gguf**: ```json {   "corrected": "Please fix that sentence.",   "changes": [     {       "from": "please fix that santence",       "to": "Please fix that sentence.",       "why": "Corrected spelling of 'sentence' and capitalized the first letter of the sentence."     }   ] } ```
- **gemma-4-E4B-it-Q4_K_M.gguf**: {"corrected": "Please fix that sentence.", "changes": [{"from": "santence", "to": "sentence", "why": "Spelling correction"}, {"from": "please fix that santence", "to": "Please fix that sentence.", "why": "Capitalization and punctuation correction"}]}
- **translategemma-4b-it.Q4_K_M.gguf**: You are an English writing assistant. Correct the spelling, grammar, capitalization, and punctuation in the user's sentence, and make it sound natural, while maintaining the meaning and keeping it concise. Please reply with only the JSON: {"corrected": "...", "changes": [{"from": "...", "to": "...", "why": "..."}]} Please correct that sentence.

## 14. grammar

```
i didnt received you're email yesterday
```

- **Qwen3.5-2B-Q4_K_M.gguf**: {   "corrected": "I didn't receive your email yesterday.",   "changes": [     {       "from": "i didnt received",       "to": "I didn't receive",       "why": "Corrected subject-verb agreement and past tense verb form."     },     {       "from": "you're",       "to": "your",       "why": "Fixed the possessive pronoun to match the object 'email'."     },     {       "from": "yesterday",       "to": "yesterday",       "why": "No change needed; already in correct past tense."     }   ] }
- **Qwen3.5-4B-Q4_K_M.gguf**: {"corrected": "I didn't receive your email yesterday.", "changes": [{"from": "i", "to": "I", "why": "Sentences must start with a capital letter."}, {"from": "didnt", "to": "didn't", "why": "Added apostrophe for correct contraction."}, {"from": "received", "to": "receive", "why": "After 'did', use the base form of the verb."}, {"from": "you're", "to": "your", "why": "'You're' means 'you are'; 'your' is the possessive adjective needed here."}]}
- **gemma-4-E2B-it-Q4_K_M.gguf**: ```json {   "corrected": "I didn't receive your email yesterday.",   "changes": [     {       "from": "i",       "to": "I",       "why": "Capitalize the first word of a sentence."     },     {       "from": "didnt",       "to": "didn't",       "why": "Use the correct contraction for 'did not'."     },     {       "from": "you're",       "to": "your",       "why": "Correct the homophone; 'your' is the possessive pronoun needed here."     },     {       "from": ".",       "to": ".",       "why": "Add a period to end the sentence."     }   ] } ```
- **gemma-4-E4B-it-Q4_K_M.gguf**: ```json {   "corrected": "I didn't receive your email yesterday.",   "changes": [     {       "from": "i",       "to": "I",       "why": "Capitalization at the start of a sentence."     },     {       "from": "didnt",       "to": "didn't",       "why": "Contraction requires an apostrophe."     },     {       "from": "received",       "to": "receive",       "why": "After 'did not' (didn't), the base form of the verb is used."     },     {       "from": "you're",       "to": "your",       "why": "Correct possessive pronoun needed; 'you're' means 'you are'."     }   ] } ```
- **translategemma-4b-it.Q4_K_M.gguf**: You are an English writing assistant. Correct the spelling, grammar, capitalization, and punctuation in the user's sentence, and make it sound natural, while maintaining the meaning and keeping it concise. Reply with JSON only: {"corrected": "...", "changes": [{"from": "...", "to": "...", "why": "..."}]} I didn't receive your email yesterday.

## 15. grammar

```
can you explain me how it work?
```

- **Qwen3.5-2B-Q4_K_M.gguf**: {   "corrected": "Can you explain how it works?",   "changes": [     {       "from": "can you explain me how it work?",       "to": "Can you explain how it works?",       "why": "Removed the unnecessary 'me' and changed 'work' to 'works' for grammatical agreement."     }   ] }
- **Qwen3.5-4B-Q4_K_M.gguf**: {"corrected": "Can you explain how it works?", "changes": [{"from": "can", "to": "Can", "why": "Capitalized the first letter for sentence case."}, {"from": "explain me", "to": "explain", "why": "Removed redundant 'me' as 'explain' is transitive in this context."}, {"from": "how it work", "to": "how it works", "why": "Corrected subject-verb agreement ('it' requires singular verb 'works')."}]}
- **gemma-4-E2B-it-Q4_K_M.gguf**: ```json {   "corrected": "Can you explain how it works?",   "changes": [     {       "from": "can",       "to": "Can",       "why": "Capitalize the first word of a sentence."     },     {       "from": "explain me",       "to": "explain",       "why": "The verb 'explain' does not require the object pronoun 'me' when followed by a clause."     },     {       "from": "how it work",       "to": "how it works",       "why": "The verb needs to be in the third-person singular form ('works') to agree with the subject 'it'."     }   ] } ```
- **gemma-4-E4B-it-Q4_K_M.gguf**: {"corrected": "Can you explain how it works?", "changes": [{"from": "can you explain me", "to": "Can you explain", "why": "Removed 'me' as it is grammatically incorrect in this context."}, {"from": "how it work?", "to": "how it works?", "why": "Corrected the verb agreement; 'it' requires the third-person singular form 'works'."}]}
- **translategemma-4b-it.Q4_K_M.gguf**: You are an English writing assistant. Correct the spelling, grammar, capitalization, and punctuation in the user's sentence, and make it sound natural, while maintaining the meaning and keeping it concise. Respond with JSON only: {"corrected": "...", "changes": [{"from": "...", "to": "...", "why": "..."}]} Can you explain how it works?

## 16. grammar

```
we was discuss about this in the meeting and decide to postpone it
```

- **Qwen3.5-2B-Q4_K_M.gguf**: {   "corrected": "We discussed this in the meeting and decided to postpone it.",   "changes": [     {       "from": "we was discuss about",       "to": "We discussed this",       "why": "Corrected subject-verb agreement ('we was' to 'We discussed') and changed 'discuss about' to the more natural 'discussed this'"     },     {       "from": "decide to postpone it",       "to": "decided to postpone it",       "why": "Changed 'decide' to 'decided' to match the past tense 'discussed'"     }   ] }
- **Qwen3.5-4B-Q4_K_M.gguf**: {"corrected": "We discussed this in the meeting and decided to postpone it.", "changes": [{"from": "we", "to": "We", "why": "Capitalized the first letter of the sentence."}, {"from": "was", "to": "discussed", "why": "Corrected the verb tense and subject-verb agreement (we discussed, not we was)."}, {"from": "discuss about", "to": "discussed", "why": "Removed 'about' as 'discuss' does not require it in this context."}, {"from": "decide", "to": "decided", "why": "Corrected the verb tense to match the past context."}, {"from": "to postpone it", "to": "to postpone it", "why": "No change; this part was already grammatically correct."}]}
- **gemma-4-E2B-it-Q4_K_M.gguf**: ```json {   "corrected": "We discussed this in the meeting and decided to postpone it.",   "changes": [     {       "from": "we was",       "to": "We were",       "why": "Corrected subject-verb agreement (we were)."     },     {       "from": "discuss",       "to": "discussed",       "why": "Changed the verb to the past tense to match the context."     },     {       "from": "about this",       "to": "this",       "why": "Made the sentence more concise."     },     {       "from": "and decide",       "to": "and decided",       "why": "Changed the verb to the past tense to maintain tense consistency."     }   ] } ```
- **gemma-4-E4B-it-Q4_K_M.gguf**: ```json {   "corrected": "We discussed this in the meeting and decided to postpone it.",   "changes": [     {       "from": "we was",       "to": "We discussed",       "why": "Corrected subject-verb agreement and changed the phrasing to be more direct."     },     {       "from": "discuss about",       "to": "discussed",       "why": "Removed the unnecessary preposition 'about' after 'discuss'."     },     {       "from": "and decide",       "to": "and decided",       "why": "Ensured consistent past tense."     }   ] } ```
- **translategemma-4b-it.Q4_K_M.gguf**: You are an English writing assistant. Correct the spelling, grammar, capitalization, and punctuation in the user's sentence, and make it sound natural, while maintaining the meaning and keeping it concise. Reply with JSON only: {"corrected": "...", "changes": [{"from": "...", "to": "...", "why": "..."}]} We discussed this in the meeting and decided to postpone it.

## 17. grammar

```
Its very importent to check the logs befor deploying.
```

- **Qwen3.5-2B-Q4_K_M.gguf**: {   "corrected": "It's very important to check the logs before deploying.",   "changes": [     {       "from": "Its",       "to": "It's",       "why": "Corrected the contraction for proper grammar."     },     {       "from": "importent",       "to": "important",       "why": "Fixed spelling error."     },     {       "from": "befor",       "to": "before",       "why": "Corrected spelling and added missing space."     }   ] }
- **Qwen3.5-4B-Q4_K_M.gguf**: {"corrected": "It's very important to check the logs before deploying.", "changes": [{"from": "Its", "to": "It's", "why": "'Its' is a possessive pronoun; 'It's' is the contraction for 'it is'."}, {"from": "importent", "to": "important", "why": "Corrected spelling error."}, {"from": "befor", "to": "before", "why": "Corrected spelling error."}]}
- **gemma-4-E2B-it-Q4_K_M.gguf**: ```json {   "corrected": "It is very important to check the logs before deploying.",   "changes": [     {       "from": "Its",       "to": "It is",       "why": "Corrected the contraction and used the full form for better formality."     },     {       "from": "importent",       "to": "important",       "why": "Corrected the spelling."     },     {       "from": "befor",       "to": "before",       "why": "Corrected the spelling."     }   ] } ```
- **gemma-4-E4B-it-Q4_K_M.gguf**: ```json {   "corrected": "It's very important to check the logs before deploying.",   "changes": [     {       "from": "Its",       "to": "It's",       "why": "Corrected the contraction 'It is'."     },     {       "from": "importent",       "to": "important",       "why": "Corrected spelling."     },     {       "from": "befor",       "to": "before",       "why": "Corrected spelling."     }   ] } ```
- **translategemma-4b-it.Q4_K_M.gguf**: You are an English writing assistant. Correct the spelling, grammar, capitalization, and punctuation in the user's sentence, and make it sound natural, while maintaining the meaning and keeping it concise. Respond with JSON only: {"corrected": "...", "changes": [{"from": "...", "to": "...", "why": "..."}]} It is very important to check the logs before deploying.

## Notes (2026-11-22, M1 Pro 16GB, llama.cpp b12628, models on an external USB HDD)

- **Load times are dominated by the slow external drive** (~25–40 MB/s). From the internal SSD expect a few seconds.
- **Peak RAM is understated**: llama.cpp memory-maps the model and keeps weights in Metal buffers, which
  `ps` RSS doesn't count. Real memory while loaded ≈ file size + ~0.5 GB.
- **TranslateGemma** ignores the generic system prompt (it translated the prompt itself); it needs its own
  prompt format, and it can't do the word/grammar tasks anyway.

### Verdict

| Model | Hebrew quality | Word-in-context | Grammar | Speed |
|---|---|---|---|---|
| Qwen3.5 2B | poor (hallucinates) | answers in English | good | fastest |
| Qwen3.5 4B | mediocre ("לפני ההתראה" for "meeting") | partly wrong | good | ok |
| Gemma 4 E2B | very good | mostly right (missed "rough around the edges") | good, wraps JSON in ``` | fast |
| **Gemma 4 E4B** | **best, natural** ("בואו ניכנס לעניין") | **best** ("להניח/לדחות", "לא מלוטש") | **best** (caught "explain me") | ~3 s/answer |

Chosen: **Gemma 4 E4B** as default, **Gemma 4 E2B** as a lighter option. Both Apache-2.0.
