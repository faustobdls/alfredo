# Match the house style

New code should read as though the people who wrote the surrounding code wrote
it. These rules govern how added code fits in.

## Discover before you write

- Read the nearby code first: naming conventions, error handling, import style,
  function shape, comment density, test layout.
- Follow whatever convention is already there, even if a different one is your
  preference.
- When two conventions coexist, follow the one used in the file you are editing.

## Fitting in

- Match comment density to the file. A file with no comments does not want a new
  paragraph of them; a heavily annotated one does.
- Use the project's existing utilities and helpers before writing new ones.
- Keep formatting consistent with the file's formatter output. Do not hand-format
  against the tool.

## When the house style is wrong

- A convention you dislike is not a defect. Leave it unless the task is to change
  it.
- If a real problem in the convention affects the task, raise it separately.
