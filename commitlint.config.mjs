export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // We use scope-prefixed commits (`scope: description`), not Conventional
    // Commit types. commitlint parses the leading token as `type`, so we allow
    // any value there and only enforce that it is present and lowercase.
    'type-enum': [0],
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'scope-empty': [0],
    // Dependabot commit bodies include long markdown URLs (changelog /
    // compare links) that can exceed the conventional default of 100.
    'body-max-line-length': [2, 'always', 200],
  },
};
