const config = {
  '*': 'prettier --ignore-unknown --write',
  'Gemfile|*.{rb,ruby,ru,rake}': 'bin/docker-rubocop --force-exclusion -a',
  '*.{js,jsx,ts,tsx}': 'eslint --fix',
  '*.{css,scss}': 'stylelint --fix',
  '*.haml': 'bin/docker-haml-lint -a',
  '**/*.ts?(x)': () => 'tsc -p tsconfig.json --noEmit',
};

module.exports = config;
