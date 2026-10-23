const CONFIG = Object.freeze({
  sessionTtlSeconds: 21600,
  loginAttemptsBeforeLock: 5,
  loginLockSeconds: 900,
  maxNameLength: 120,
  maxEmailLength: 254,
  maxPasswordLength: 256,
  maxProfileImageBytes: 307200,
});

const PORTAL_ROLES = Object.freeze(['Admin', 'Collector', 'Member']);
const ROLE_PERMISSION_KEYS = Object.freeze([
  'shared_data_read',
  'own_collection_read',
  'collection_manage',
  'deposit_view',
  'deposit_manage',
  'ledger_manage',
  'user_manage',
]);

const SHEETS = Object.freeze({
  Users: [
    'id',
    'accountNo',
    'name',
    'profileImageUrl',
    'profileImageFileId',
    'email',
    'role',
    'passwordSalt',
    'passwordHash',
    'active',
    'dailyAccess',
    'weeklyAccess',
    'monthlyAccess',
    'createdAt',
  ],
  Role_Permissions: ['role', ...ROLE_PERMISSION_KEYS],
  Amount: [
    'date',
    'byWhom',
    'remarks',
    'deposit',
    'withdrawal',
    'balance',
    'payMode',
    'entryBy',
  ],
  Daily_Collection: collectionHeaders_(365),
  Weekly_Collection: collectionHeaders_(52),
  Monthly_Collection: collectionHeaders_(12),
  Deposit_Accounts: [
    'id',
    'memberName',
    'product',
    'cadence',
    'startDate',
    'amount',
    'annualRate',
    'tenureMonths',
    'maturityDate',
    'maturityAmount',
    'payments',
    'createdAt',
    'createdBy',
  ],
});

function collectionHeaders_(count) {
  const headers = [
    'memberName',
    'date',
    'depAmt',
    'totalCount',
    'totalReceived',
    'grandTotal',
  ];
  for (let index = 1; index <= count; index++) headers.push(`P${index}`);
  return headers;
}

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('NTCCSL Portal')
    .addItem('Set up portal sheets', 'setupAccountPortal')
    .addItem('Create first admin', 'createInitialAdmin')
    .addItem('Reset admin password', 'resetAdminPassword')
    .addToUi();
}

function setupAccountPortal() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) {
    throw new Error('Open this script from the Google Sheet before running setup.');
  }
  const properties = PropertiesService.getScriptProperties();
  properties.setProperty('SPREADSHEET_ID', spreadsheet.getId());
  if (!properties.getProperty('PASSWORD_PEPPER')) {
    properties.setProperty(
      'PASSWORD_PEPPER',
      `${Utilities.getUuid()}${Utilities.getUuid()}${Utilities.getUuid()}`,
    );
  }
  migrateLegacyWorkbook_(spreadsheet);
  Object.keys(SHEETS).forEach((name) => {
    const sheet = spreadsheet.getSheetByName(name) || spreadsheet.insertSheet(name);
    ensureHeaders_(sheet, SHEETS[name]);
    sheet.setFrozenRows(1);
  });
  initializeRolePermissionsSheet_();
  backfillAccountNumbers_();
  getOrCreateProfileImagesFolder_();
  spreadsheet.toast('Portal sheets are ready.', 'NTCCSL Portal', 5);
}

function createInitialAdmin() {
  const ui = SpreadsheetApp.getUi();
  const users = getSpreadsheet_().getSheetByName('Users');
  if (!users) {
    throw new Error('Run setupAccountPortal before creating the first admin.');
  }
  if (users.getLastRow() > 1) {
    throw new Error('The Users sheet is not empty. Use an existing admin account.');
  }
  const emailResponse = ui.prompt(
    'Create first admin',
    'Enter the admin email address:',
    ui.ButtonSet.OK_CANCEL,
  );
  if (emailResponse.getSelectedButton() !== ui.Button.OK) return;
  const nameResponse = ui.prompt(
    'Create first admin',
    'Enter the admin display name:',
    ui.ButtonSet.OK_CANCEL,
  );
  if (nameResponse.getSelectedButton() !== ui.Button.OK) return;
  const passwordResponse = ui.prompt(
    'Create first admin',
    'Enter a strong password (at least 12 characters):',
    ui.ButtonSet.OK_CANCEL,
  );
  if (passwordResponse.getSelectedButton() !== ui.Button.OK) return;
  const email = normalizeEmail_(emailResponse.getResponseText());
  const name = cleanText_(nameResponse.getResponseText(), CONFIG.maxNameLength);
  const password = passwordResponse.getResponseText();
  validateRegistration_(name, email, password, 12);
  createUser_({ name, email, password, role: 'Admin' });
  ui.alert('Admin account created. Sign in using the email and password.');
}

function resetAdminPassword() {
  const ui = SpreadsheetApp.getUi();
  const emailResponse = ui.prompt(
    'Reset admin password',
    'Enter the email address of an existing active admin:',
    ui.ButtonSet.OK_CANCEL,
  );
  if (emailResponse.getSelectedButton() !== ui.Button.OK) return;

  const user = findUserByEmail_(normalizeEmail_(emailResponse.getResponseText()));
  if (!user || user.role !== 'Admin' || !isActive_(user.active)) {
    throw new Error('No active admin account was found for that email.');
  }

  const passwordResponse = ui.prompt(
    'Reset admin password',
    'Enter a new password (at least 12 characters):',
    ui.ButtonSet.OK_CANCEL,
  );
  if (passwordResponse.getSelectedButton() !== ui.Button.OK) return;

  const password = passwordResponse.getResponseText();
  validatePassword_(password, 12);
  withScriptLock_(() => setUserPassword_(user.id, password));
  ui.alert('Admin password reset. Sign in using the new password.');
}

function setUserPassword_(userId, password) {
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User account was not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const salt = Utilities.getUuid();
  setField_(sheet, row, headers, 'passwordSalt', salt);
  setField_(
    sheet,
    row,
    headers,
    'passwordHash',
    passwordHash_(password, salt, getPasswordPepper_()),
  );
}

function migrateLegacyWorkbook_(spreadsheet) {
  ['Amount', 'Anount'].forEach((sheetName) => {
    const source = spreadsheet.getSheetByName(sheetName);
    if (!source || !isLegacyAmountSheet_(source)) return;
    const records = readLegacyAmountRecords_(source);
    archiveLegacySheet_(source);
    const target =
      spreadsheet.getSheetByName('Amount') || spreadsheet.insertSheet('Amount');
    ensureHeaders_(target, SHEETS.Amount);
    appendRecords_(target, SHEETS.Amount, records);
  });

  ['Daily_Collection', 'Weekly_Collection', 'Monthly_Collection'].forEach(
    (sheetName) => {
      const source = spreadsheet.getSheetByName(sheetName);
      if (!source || !isLegacyCollectionSheet_(source)) return;
      const records = readLegacyCollectionRecords_(source, sheetName);
      archiveLegacySheet_(source);
      const target =
        spreadsheet.getSheetByName(sheetName) ||
        spreadsheet.insertSheet(sheetName);
      ensureHeaders_(target, SHEETS[sheetName]);
      appendRecords_(target, SHEETS[sheetName], records);
    },
  );
}

function isLegacyAmountSheet_(sheet) {
  const headers = getSheetHeaderValues_(sheet).map(normalizeHeaderKey_);
  return (
    legacyHeaderIndex_(headers, ['by whom']) >= 0 &&
    legacyHeaderIndex_(headers, ['withdrawal', 'withdrawl']) >= 0 &&
    legacyHeaderIndex_(headers, ['pay mode', 'payment mode']) >= 0
  );
}

function readLegacyAmountRecords_(sheet) {
  const headers = getSheetHeaderValues_(sheet);
  const fields = {
    date: ['date'],
    byWhom: ['by whom'],
    remarks: ['remarks'],
    deposit: ['deposit'],
    withdrawal: ['withdrawal', 'withdrawl'],
    balance: ['balance'],
    payMode: ['pay mode', 'payment mode'],
    entryBy: ['entry by'],
  };
  const columns = {};
  Object.keys(fields).forEach((field) => {
    columns[field] = legacyHeaderIndex_(headers, fields[field]);
  });
  ['date', 'deposit', 'withdrawal', 'payMode'].forEach((field) => {
    if (columns[field] < 0) {
      throw new Error(`Cannot import the legacy ledger: missing ${field} column.`);
    }
  });

  if (sheet.getLastRow() < 2) return [];
  return sheet
    .getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn())
    .getValues()
    .reduce((records, row) => {
      const hasEntry = [
        'date',
        'byWhom',
        'remarks',
        'deposit',
        'withdrawal',
        'payMode',
        'entryBy',
      ].some((field) => columns[field] >= 0 && row[columns[field]] !== '');
      if (!hasEntry) return records;
      const record = {};
      Object.keys(columns).forEach((field) => {
        if (columns[field] >= 0) record[field] = row[columns[field]];
      });
      records.push(record);
      return records;
    }, []);
}

function isLegacyCollectionSheet_(sheet) {
  const headers = getSheetHeaderValues_(sheet);
  return (
    legacyHeaderIndex_(headers, ['name members', 'member name']) >= 0 &&
    legacyHeaderIndex_(headers, ['dep amt', 'deposit amount']) >= 0 &&
    legacyHeaderIndex_(headers, ['total days']) >= 0
  );
}

function readLegacyCollectionRecords_(sheet, sheetName) {
  const headers = getSheetHeaderValues_(sheet);
  const dateColumn = legacyHeaderIndex_(headers, [
    'date',
    'deposit open date',
  ]);
  const nameColumn = legacyHeaderIndex_(headers, ['name members', 'member name']);
  const amountColumn = legacyHeaderIndex_(headers, ['dep amt', 'deposit amount']);
  const totalDaysColumn = legacyHeaderIndex_(headers, ['total days']);
  const expectedPeriodCount = SHEETS[sheetName].filter((header) =>
    /^P\d+$/i.test(header),
  ).length;
  const periodCount = totalDaysColumn - 3;
  if (
    dateColumn < 0 ||
    nameColumn < 0 ||
    amountColumn < 0 ||
    periodCount !== expectedPeriodCount
  ) {
    throw new Error(
      `Cannot import ${sheetName}: its legacy columns do not match the expected layout.`,
    );
  }
  if (sheet.getLastRow() < 3) return [];

  const rows = sheet
    .getRange(3, 1, sheet.getLastRow() - 2, sheet.getLastColumn())
    .getValues();
  return rows.reduce((records, row) => {
    const memberName = row[nameColumn];
    if (memberName === '' || memberName === null) return records;
    const periods = [];
    for (let index = 0; index < periodCount; index++) {
      periods.push(isPaid_(row[index + 3]));
    }
    records.push({
      memberName,
      date: row[dateColumn],
      depAmt: row[amountColumn],
      totalCount: periods.filter(Boolean).length,
      totalReceived:
        periods.filter(Boolean).length * (Number(row[amountColumn]) || 0),
      grandTotal: 0,
      ...Object.fromEntries(
        periods.map((isPaid, index) => [`P${index + 1}`, isPaid]),
      ),
    });
    return records;
  }, []);
}

function getSheetHeaderValues_(sheet) {
  if (sheet.getLastColumn() < 1) return [];
  return sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
}

function normalizeHeaderKey_(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function legacyHeaderIndex_(headers, aliases) {
  const normalizedAliases = aliases.map(normalizeHeaderKey_);
  return headers.findIndex((header) =>
    normalizedAliases.includes(normalizeHeaderKey_(header)),
  );
}

function archiveLegacySheet_(sheet) {
  const spreadsheet = sheet.getParent();
  const baseName = `${sheet.getName()}_Legacy`;
  let archiveName = baseName;
  let suffix = 2;
  while (spreadsheet.getSheetByName(archiveName)) {
    archiveName = `${baseName}_${suffix}`;
    suffix += 1;
  }
  sheet.setName(archiveName);
}

function appendRecords_(sheet, headers, records) {
  if (records.length === 0) return;
  const firstRow = sheet.getLastRow() + 1;
  const rows = records.map((record) =>
    headers.map((header) =>
      Object.prototype.hasOwnProperty.call(record, header)
        ? safeCellValue_(record[header])
        : '',
    ),
  );
  sheet.getRange(firstRow, 1, rows.length, headers.length).setValues(rows);
}

function doGet() {
  return jsonOutput_({
    status: 'success',
    service: 'NTCCSL Account Portal',
    message: 'Send application actions as JSON POST requests.',
  });
}

function doPost(event) {
  try {
    if (!event || !event.postData || !event.postData.contents) {
      throw new Error('Expected a JSON request body.');
    }
    const request = JSON.parse(event.postData.contents);
    if (!request || typeof request !== 'object' || Array.isArray(request)) {
      throw new Error('Request body must be a JSON object.');
    }
    return jsonOutput_(dispatch_(request));
  } catch (error) {
    console.error(error && error.stack ? error.stack : String(error));
    return jsonOutput_({ status: 'error', message: safeErrorMessage_(error) });
  }
}

function dispatch_(request) {
  const action = String(request.action || '');
  switch (action) {
    case 'login':
      return login_(request);
    case 'register':
      return register_(request);
    case 'getAmount':
      requireAnyPermission_(request.token, ['shared_data_read', 'ledger_manage']);
      return readAmount_();
    case 'getDaily':
      return readCollectionForUser_(
        'Daily_Collection',
        requireCollectionRead_(request.token, 'dailyAccess'),
      );
    case 'getWeekly':
      return readCollectionForUser_(
        'Weekly_Collection',
        requireCollectionRead_(request.token, 'weeklyAccess'),
      );
    case 'getMonthly':
      return readCollectionForUser_(
        'Monthly_Collection',
        requireCollectionRead_(request.token, 'monthlyAccess'),
      );
    case 'getDepositAccounts': {
      const { product, cadence } = validateDepositProductCadence_(
        request.product,
        request.cadence,
      );
      const user = requireDepositRead_(request.token, cadence);
      return readDepositAccounts_(product, cadence, user);
    }
    case 'getUsers':
      requireAnyPermission_(request.token, ['shared_data_read', 'user_manage']);
      return readUsers_();
    case 'addAmount':
      requirePermission_(request.token, 'ledger_manage');
      return withScriptLock_(() => addAmount_(request));
    case 'editAmount':
      requirePermission_(request.token, 'ledger_manage');
      return withScriptLock_(() => editAmount_(request));
    case 'deleteAmount':
      requirePermission_(request.token, 'ledger_manage');
      return withScriptLock_(() => deleteAmount_(request));
    case 'addCollection':
      requirePermission_(request.token, 'collection_manage');
      return withScriptLock_(() => addCollection_(request));
    case 'editCollection':
      requirePermission_(request.token, 'collection_manage');
      return withScriptLock_(() => editCollection_(request));
    case 'deleteCollection':
      requirePermission_(request.token, 'collection_manage');
      return withScriptLock_(() => deleteCollection_(request));
    case 'toggleCollection':
      requirePermission_(request.token, 'collection_manage');
      return withScriptLock_(() => toggleCollection_(request));
    case 'addDepositAccount': {
      const user = requirePermission_(request.token, 'deposit_manage');
      return withScriptLock_(() => addDepositAccount_(request, user));
    }
    case 'editDepositAccount':
      requirePermission_(request.token, 'deposit_manage');
      return withScriptLock_(() => editDepositAccount_(request));
    case 'toggleDepositPayment':
      requirePermission_(request.token, 'deposit_manage');
      return withScriptLock_(() => toggleDepositPayment_(request));
    case 'deleteDepositAccount':
      requirePermission_(request.token, 'deposit_manage');
      return withScriptLock_(() => deleteDepositAccount_(request));
    case 'addUser':
      {
        const user = requirePermission_(request.token, 'user_manage');
        return withScriptLock_(() => addUser_(request, user));
      }
    case 'editUser':
      {
        const user = requirePermission_(request.token, 'user_manage');
        return withScriptLock_(() => editUser_(request, user));
      }
    case 'deleteUser':
      {
        const user = requirePermission_(request.token, 'user_manage');
        return withScriptLock_(() => deleteUser_(request, user));
      }
    case 'updateMyProfile': {
      const user = requireRole_(request.token, ['Admin', 'Collector', 'Member']);
      return withScriptLock_(() => updateMyProfile_(request, user));
    }
    case 'getRolePermissions':
      requireRole_(request.token, ['Admin']);
      return { status: 'success', permissions: rolePermissions_() };
    case 'setRolePermissions':
      requireRole_(request.token, ['Admin']);
      return withScriptLock_(() => setRolePermissions_(request.permissions));
    case 'changePassword': {
      const user = requireRole_(request.token, ['Admin', 'Collector', 'Member']);
      return withScriptLock_(() => changePassword_(request, user));
    }
    default:
      throw new Error(`Unknown post action: ${action || '(missing)'}`);
  }
}

function register_(request) {
  return withScriptLock_(() => {
    const name = cleanText_(request.name, CONFIG.maxNameLength);
    const email = normalizeEmail_(request.email);
    const password = String(request.password || '');
    validateRegistration_(name, email, password, 8);
    assertUniqueMemberName_(name);
    if (findUserByEmail_(email)) {
      throw new Error('An account with this email already exists.');
    }
    createUser_({ name, email, password, role: 'Member' });
    return { status: 'success' };
  });
}

function login_(request) {
  const email = normalizeEmail_(request.email);
  const password = String(request.password || '');
  if (!email || !password) throw new Error('Enter your email and password.');

  const cache = CacheService.getScriptCache();
  const attemptKey = `login:${sha256Hex_(email)}`;
  const attempts = Number(cache.get(attemptKey) || 0);
  if (attempts >= CONFIG.loginAttemptsBeforeLock) {
    throw new Error('Too many sign-in attempts. Try again in 15 minutes.');
  }

  const user = findUserByEmail_(email);
  const candidate = passwordHash_(
    password,
    user ? user.passwordSalt : 'unknown-user-salt',
    getPasswordPepper_(),
  );
  if (
    !user ||
    !isActive_(user.active) ||
    !constantTimeEquals_(candidate, user.passwordHash)
  ) {
    cache.put(attemptKey, String(attempts + 1), CONFIG.loginLockSeconds);
    throw new Error('Invalid email or password.');
  }

  const loginType = String(request.loginType || '');
  if (
    (loginType === 'member' && user.role !== 'Member') ||
    (loginType === 'staff' &&
      user.role !== 'Admin' &&
      user.role !== 'Collector') ||
    (loginType && loginType !== 'member' && loginType !== 'staff')
  ) {
    throw new Error(
      loginType === 'member'
        ? 'This login is for Member accounts. Choose Admin / Collector login instead.'
        : 'This login is for Admin and Collector accounts. Choose Member login instead.',
    );
  }

  cache.remove(attemptKey);
  const token = `${Utilities.getUuid()}${Utilities.getUuid()}`;
  cache.put(
    `session:${sha256Hex_(token)}`,
    JSON.stringify({ userId: user.id }),
    CONFIG.sessionTtlSeconds,
  );
  return {
    status: 'success',
    token,
    user: publicUser_(user),
    permissions: permissionsForUser_(user),
    reportAccess: reportAccessForUser_(user),
  };
}

function reportAccessForUser_(user) {
  return {
    daily: isReportAccessEnabled_(user.dailyAccess),
    weekly: isReportAccessEnabled_(user.weeklyAccess),
    monthly: isReportAccessEnabled_(user.monthlyAccess),
  };
}

function isReportAccessEnabled_(value) {
  if (value === '' || value === null || value === undefined) return true;
  return value === true || String(value).toLowerCase() === 'true';
}

function defaultRolePermissions_() {
  const allPermissions = Object.fromEntries(
    ROLE_PERMISSION_KEYS.map((key) => [key, true]),
  );
  return {
    Collector: { ...allPermissions },
    Member: memberRolePermissions_(),
  };
}

function memberRolePermissions_() {
  return Object.fromEntries(
    ROLE_PERMISSION_KEYS.map((key) => [
      key,
      key === 'own_collection_read' || key === 'deposit_view',
    ]),
  );
}

function normalizeMemberRolePermissions_(permissions) {
  return {
    shared_data_read: permissions.shared_data_read === true,
    own_collection_read:
      typeof permissions.own_collection_read === 'boolean'
        ? permissions.own_collection_read
        : true,
    collection_manage: false,
    deposit_view: permissions.deposit_view === true,
    deposit_manage: false,
    ledger_manage: false,
    user_manage: false,
  };
}

function legacyDepositPermissionDefault_(role, key, permissions) {
  if (key === 'deposit_manage') {
    return role !== 'Member' && permissions.collection_manage === true;
  }
  if (key === 'deposit_view') {
    return (
      permissions.shared_data_read === true ||
      permissions.own_collection_read === true ||
      permissions.collection_manage === true
    );
  }
  return undefined;
}

function rolePermissionFromRecord_(record, role, key) {
  const value = record[key];
  if (value === '' || value === null || value === undefined) {
    const legacyDefault = legacyDepositPermissionDefault_(role, key, record);
    if (legacyDefault !== undefined) return legacyDefault;
  }
  return parseRolePermissionValue_(value, role, key);
}

function rolePermissions_() {
  initializeRolePermissionsSheet_();
  const records = readRecords_('Role_Permissions');
  const permissions = Object.fromEntries(
    ['Collector', 'Member'].map((role) => {
      const matchingRecords = records.filter(
        (record) => String(record.role).trim().toLowerCase() === role.toLowerCase(),
      );
      if (matchingRecords.length !== 1) {
        throw new Error(
          `The Role_Permissions sheet must contain one ${role} row. Run setupAccountPortal.`,
        );
      }
      const record = matchingRecords[0];
      return [
        role,
        Object.fromEntries(
          ROLE_PERMISSION_KEYS.map((key) => [
            key,
            rolePermissionFromRecord_(record, role, key),
          ]),
        ),
      ];
    }),
  );
  permissions.Member = normalizeMemberRolePermissions_(permissions.Member);
  return permissions;
}

function permissionsForUser_(user) {
  if (user.role === 'Admin') {
    return Object.fromEntries(ROLE_PERMISSION_KEYS.map((key) => [key, true]));
  }
  return rolePermissions_()[user.role] || {};
}

function setRolePermissions_(permissions) {
  if (!permissions || typeof permissions !== 'object' || Array.isArray(permissions)) {
    throw new Error('Provide permission settings for each role.');
  }
  const normalized = {};
  ['Collector', 'Member'].forEach((role) => {
    const roleSettings = permissions[role];
    if (!roleSettings || typeof roleSettings !== 'object' || Array.isArray(roleSettings)) {
      throw new Error(`Provide permission settings for ${role}.`);
    }
    normalized[role] = {};
    ROLE_PERMISSION_KEYS.forEach((key) => {
      if (typeof roleSettings[key] !== 'boolean') {
        throw new Error(`Permission ${key} for ${role} must be true or false.`);
      }
      normalized[role][key] = roleSettings[key];
    });
  });
  normalized.Member = normalizeMemberRolePermissions_(normalized.Member);
  const sheet = ensureRolePermissionsSheet_();
  const headers = getHeaders_(sheet);
  ['Collector', 'Member'].forEach((role) => {
    const rows = readRecords_('Role_Permissions').filter(
      (record) => String(record.role).trim().toLowerCase() === role.toLowerCase(),
    );
    if (rows.length > 1) {
      throw new Error(`The Role_Permissions sheet contains duplicate ${role} rows.`);
    }
    const values = headers.map((header) =>
      header === 'role' ? role : normalized[role][header] ?? '',
    );
    if (rows.length === 1) {
      sheet.getRange(rows[0].__rowIndex, 1, 1, headers.length).setValues([values]);
    } else {
      sheet.appendRow(values);
    }
  });
  PropertiesService.getScriptProperties().setProperty(
    'ROLE_PERMISSIONS',
    JSON.stringify(normalized),
  );
  return { status: 'success', permissions: normalized };
}

function initializeRolePermissionsSheet_() {
  const sheet = ensureRolePermissionsSheet_();
  const records = readRecords_('Role_Permissions');
  let storedPermissions;
  const headers = getHeaders_(sheet);
  ['Collector', 'Member'].forEach((role) => {
    const matchingRecords = records.filter(
      (record) => String(record.role).trim().toLowerCase() === role.toLowerCase(),
    );
    if (matchingRecords.length > 1) {
      throw new Error(`The Role_Permissions sheet contains duplicate ${role} rows.`);
    }
    let settings;
    if (matchingRecords.length === 1) {
      settings = Object.fromEntries(
        ROLE_PERMISSION_KEYS.map((key) => [
          key,
          rolePermissionFromRecord_(matchingRecords[0], role, key),
        ]),
      );
    } else {
      if (!storedPermissions) {
        storedPermissions = rolePermissionsFromProperties_();
      }
      settings = storedPermissions[role];
    }
    if (role === 'Member') {
      settings = normalizeMemberRolePermissions_(settings);
    }
    const values = headers.map((header) =>
      header === 'role' ? role : settings[header] ?? '',
    );
    if (matchingRecords.length === 1) {
      sheet
        .getRange(matchingRecords[0].__rowIndex, 1, 1, headers.length)
        .setValues([values]);
    } else {
      sheet.appendRow(values);
    }
  });
}

function ensureRolePermissionsSheet_() {
    const spreadsheet = getSpreadsheet_();
    const sheet =
      spreadsheet.getSheetByName('Role_Permissions') ||
      spreadsheet.insertSheet('Role_Permissions');
    ensureHeaders_(sheet, SHEETS.Role_Permissions);
    sheet.setFrozenRows(1);
    return sheet;
}

function rolePermissionsFromProperties_() {
  const stored = PropertiesService.getScriptProperties().getProperty(
    'ROLE_PERMISSIONS',
  );
  if (!stored) return defaultRolePermissions_();
  let parsed;
  try {
    parsed = JSON.parse(stored);
  } catch (error) {
    console.error(`Invalid ROLE_PERMISSIONS setting: ${error}`);
    throw new Error('Role permissions are invalid. Contact an administrator.');
  }
  return Object.fromEntries(
    ['Collector', 'Member'].map((role) => [
      role,
      Object.fromEntries(
        ROLE_PERMISSION_KEYS.map((key) => {
          const value = parsed && parsed[role] && parsed[role][key];
          if (
            (value === undefined || value === null) &&
            legacyDepositPermissionDefault_(
              role,
              key,
              parsed && parsed[role] ? parsed[role] : {},
            ) !== undefined
          ) {
            return [
              key,
              legacyDepositPermissionDefault_(
                role,
                key,
                parsed && parsed[role] ? parsed[role] : {},
              ),
            ];
          }
          if (typeof value !== 'boolean') {
            throw new Error(
              `Stored permission ${key} for ${role} must be true or false.`,
            );
          }
          return [key, value];
        }),
      ),
    ]),
  );
}

function parseRolePermissionValue_(value, role, key) {
  if (typeof value === 'boolean') return value;
  if (value === 'TRUE' || value === 'true') return true;
  if (value === 'FALSE' || value === 'false') return false;
  throw new Error(
    `Permission ${key} for ${role} in Role_Permissions must be true or false.`,
  );
}

function readUsers_() {
  return readRecords_('Users')
    .filter((user) => isActive_(user.active))
    .map(publicUser_);
}

function addUser_(request, authenticatedUser) {
  const name = cleanText_(request.name, CONFIG.maxNameLength);
  const email = normalizeEmail_(request.email);
  const password = String(request.password || '');
  const role =
    authenticatedUser.role === 'Admin'
      ? normalizeRole_(request.role)
      : 'Member';
  validateRegistration_(name, email, password, 8);
  if (role === 'Member') assertUniqueMemberName_(name);
  if (findUserByEmail_(email)) {
    throw new Error('An account with this email already exists.');
  }
  createUser_({
    name,
    profileImageData: request.profileImageData,
    profileImageMimeType: request.profileImageMimeType,
    email,
    password,
    role,
    dailyAccess:
      role === 'Member' && authenticatedUser.role === 'Admin'
        ? requestedReportAccess_(request, 'dailyAccess')
        : true,
    weeklyAccess:
      role === 'Member' && authenticatedUser.role === 'Admin'
        ? requestedReportAccess_(request, 'weeklyAccess')
        : true,
    monthlyAccess:
      role === 'Member' && authenticatedUser.role === 'Admin'
        ? requestedReportAccess_(request, 'monthlyAccess')
        : true,
  });
  return { status: 'success' };
}

function editUser_(request, authenticatedUser) {
  const userId = requiredText_(request.userId, 'User ID');
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  const name = cleanText_(request.name, CONFIG.maxNameLength);
  const email = normalizeEmail_(request.email);
  const role =
    authenticatedUser.role === 'Admin'
      ? normalizeRole_(request.role)
      : String(user.role || '');
  if (authenticatedUser.role !== 'Admin' && user.role === 'Admin') {
    throw new Error('Only an administrator can manage admin accounts.');
  }
  validateNameAndEmail_(name, email);
  if (role === 'Member') assertUniqueMemberName_(name, userId);
  const duplicate = findUserByEmail_(email);
  if (duplicate && String(duplicate.id) !== userId) {
    throw new Error('An account with this email already exists.');
  }
  if (isActive_(user.active) && user.role === 'Admin' && role !== 'Admin') {
    assertAnotherActiveAdmin_(userId);
  }
  const imageChanged = request.profileImageChanged === true;
  let replacementImageFileId = String(user.profileImageFileId || '');
  if (imageChanged) {
    if (!request.profileImageData && request.profileImageMimeType !== undefined) {
      throw new Error('Profile image data is required when a MIME type is provided.');
    }
    replacementImageFileId = request.profileImageData
      ? saveProfileImage_(
          request.profileImageData,
          request.profileImageMimeType,
          userId,
        )
      : '';
  } else if (
    request.profileImageChanged !== undefined ||
    request.profileImageData !== undefined ||
    request.profileImageMimeType !== undefined
  ) {
    throw new Error('profileImageChanged must be true or omitted.');
  }
  const updatedUser = Object.assign({}, user, {
    name,
    email,
    role,
    accountNo:
      role === user.role ? String(user.accountNo || '') : nextAccountNumber_(role),
    profileImageFileId: replacementImageFileId,
    profileImageUrl: imageChanged ? '' : String(user.profileImageUrl || ''),
  });
  if (authenticatedUser.role === 'Admin') {
    updatedUser.dailyAccess = reportAccessForEdit_(
      role,
      user,
      request,
      'dailyAccess',
    );
    updatedUser.weeklyAccess = reportAccessForEdit_(
      role,
      user,
      request,
      'weeklyAccess',
    );
    updatedUser.monthlyAccess = reportAccessForEdit_(
      role,
      user,
      request,
      'monthlyAccess',
    );
  }
  if (request.password !== undefined && String(request.password) !== '') {
    const password = String(request.password);
    validatePassword_(password, 8);
    const salt = Utilities.getUuid();
    updatedUser.passwordSalt = salt;
    updatedUser.passwordHash = passwordHash_(
      password,
      salt,
      getPasswordPepper_(),
    );
  }
  const updatedValues = headers.map((header) =>
    Object.prototype.hasOwnProperty.call(updatedUser, header)
      ? safeCellValue_(updatedUser[header])
      : '',
  );
  try {
    sheet.getRange(row, 1, 1, headers.length).setValues([updatedValues]);
  } catch (error) {
    if (imageChanged && replacementImageFileId) {
      trashProfileImage_(replacementImageFileId);
    }
    throw error;
  }
  if (
    imageChanged &&
    user.profileImageFileId &&
    user.profileImageFileId !== replacementImageFileId
  ) {
    trashProfileImage_(user.profileImageFileId);
  }
  return { status: 'success' };
}

function updateMyProfile_(request, authenticatedUser) {
  const userId = String(authenticatedUser.id);
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User account was not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  const name = cleanText_(request.name, CONFIG.maxNameLength);
  const email = normalizeEmail_(request.email);
  validateNameAndEmail_(name, email);
  if (user.role === 'Member') {
    if (normalizeMemberName_(name) !== normalizeMemberName_(user.name)) {
      throw new Error('Contact an administrator to change your member name.');
    }
    assertUniqueMemberName_(name, userId);
  }
  const duplicate = findUserByEmail_(email);
  if (duplicate && String(duplicate.id) !== userId) {
    throw new Error('An account with this email already exists.');
  }

  const imageChanged = request.profileImageChanged === true;
  let replacementImageFileId = String(user.profileImageFileId || '');
  if (imageChanged) {
    if (!request.profileImageData && request.profileImageMimeType !== undefined) {
      throw new Error('Profile image data is required when a MIME type is provided.');
    }
    replacementImageFileId = request.profileImageData
      ? saveProfileImage_(
          request.profileImageData,
          request.profileImageMimeType,
          userId,
        )
      : '';
  } else if (
    request.profileImageChanged !== undefined ||
    request.profileImageData !== undefined ||
    request.profileImageMimeType !== undefined
  ) {
    throw new Error('profileImageChanged must be true or omitted.');
  }

  const updatedUser = Object.assign({}, user, { name, email });
  if (imageChanged) {
    updatedUser.profileImageFileId = replacementImageFileId;
    updatedUser.profileImageUrl = '';
  }
  const updatedValues = headers.map((header) =>
    Object.prototype.hasOwnProperty.call(updatedUser, header)
      ? safeCellValue_(updatedUser[header])
      : '',
  );
  try {
    sheet.getRange(row, 1, 1, headers.length).setValues([updatedValues]);
  } catch (error) {
    if (imageChanged && replacementImageFileId) {
      trashProfileImage_(replacementImageFileId);
    }
    throw error;
  }
  if (
    imageChanged &&
    user.profileImageFileId &&
    user.profileImageFileId !== replacementImageFileId
  ) {
    trashProfileImage_(user.profileImageFileId);
  }
  return { status: 'success' };
}

function requestedReportAccess_(request, key) {
  const value = request[key];
  if (value === undefined) return true;
  if (typeof value !== 'boolean') {
    throw new Error(`${key} must be true or false.`);
  }
  return value;
}

function reportAccessForEdit_(role, user, request, key) {
  if (role !== 'Member') return true;
  if (request[key] === undefined) {
    return isReportAccessEnabled_(user[key]);
  }
  return requestedReportAccess_(request, key);
}

function deleteUser_(request, authenticatedUser) {
  const userId = requiredText_(request.userId, 'User ID');
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  if (authenticatedUser.role !== 'Admin' && user.role === 'Admin') {
    throw new Error('Only an administrator can manage admin accounts.');
  }
  if (isActive_(user.active) && user.role === 'Admin') {
    assertAnotherActiveAdmin_(userId);
  }
  sheet.deleteRow(row);
  return { status: 'success' };
}

function changePassword_(request, authenticatedUser) {
  const userId = String(authenticatedUser.id);
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User account was not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  const currentPassword = String(request.currentPassword || '');
  const newPassword = String(request.newPassword || '');
  if (!currentPassword || !newPassword) {
    throw new Error('Enter your current password and a new password.');
  }
  const pepper = getPasswordPepper_();
  const currentHash = passwordHash_(
    currentPassword,
    user.passwordSalt,
    pepper,
  );
  if (!constantTimeEquals_(currentHash, user.passwordHash)) {
    throw new Error('Current password is incorrect.');
  }
  validatePassword_(newPassword, 8);
  if (constantTimeEquals_(
    passwordHash_(newPassword, user.passwordSalt, pepper),
    user.passwordHash,
  )) {
    throw new Error('Choose a new password different from your current one.');
  }
  const salt = Utilities.getUuid();
  setField_(sheet, row, headers, 'passwordSalt', salt);
  setField_(
    sheet,
    row,
    headers,
    'passwordHash',
    passwordHash_(newPassword, salt, pepper),
  );
  return { status: 'success' };
}

function addAmount_(request) {
  const deposit = parseNonNegativeNumber_(request.deposit, 'Deposit');
  const withdrawal = parseNonNegativeNumber_(request.withdrawal, 'Withdrawal');
  if ((deposit > 0) === (withdrawal > 0)) {
    throw new Error('Enter either a deposit or a withdrawal, but not both.');
  }
  const balance =
    request.balance === '' || request.balance === undefined
      ? ''
      : parseNonNegativeNumber_(request.balance, 'Balance');
  const sheet = getSpreadsheet_().getSheetByName('Amount');
  if (!sheet) throw new Error('Missing sheet: Amount. Run setupAccountPortal.');
  appendRecord_(sheet, getHeaders_(sheet), {
    date: request.date
      ? parseDateField_(request.date, 'Date')
      : formatDate_(new Date()),
    byWhom: cleanText_(request.byWhom, CONFIG.maxNameLength),
    remarks: cleanText_(request.remarks, 1000),
    deposit,
    withdrawal,
    balance,
    payMode: requiredText_(request.payMode, 'Payment mode'),
    entryBy: cleanText_(request.entryBy, CONFIG.maxNameLength),
  });
  return { status: 'success' };
}

function editAmount_(request) {
  const sheet = getSpreadsheet_().getSheetByName('Amount');
  if (!sheet) throw new Error('Missing sheet: Amount. Run setupAccountPortal.');
  const headers = getHeaders_(sheet);
  const rowIndex = Number(request.rowIndex);
  if (
    !Number.isInteger(rowIndex) ||
    rowIndex < 2 ||
    rowIndex > sheet.getLastRow()
  ) {
    throw new Error('Invalid ledger row.');
  }

  const deposit = parseNonNegativeNumber_(request.deposit, 'Deposit');
  const withdrawal = parseNonNegativeNumber_(request.withdrawal, 'Withdrawal');
  if ((deposit > 0) === (withdrawal > 0)) {
    throw new Error('Enter either a deposit or a withdrawal, but not both.');
  }
  const balance =
    request.balance === '' || request.balance === undefined
      ? ''
      : parseNonNegativeNumber_(request.balance, 'Balance');
  const date = parseDateField_(request.date, 'Date');
  setField_(sheet, rowIndex, headers, 'date', date);
  setField_(sheet, rowIndex, headers, 'byWhom', cleanText_(request.byWhom, CONFIG.maxNameLength));
  setField_(sheet, rowIndex, headers, 'remarks', cleanText_(request.remarks, 1000));
  setField_(sheet, rowIndex, headers, 'deposit', deposit);
  setField_(sheet, rowIndex, headers, 'withdrawal', withdrawal);
  setField_(sheet, rowIndex, headers, 'balance', balance);
  setField_(sheet, rowIndex, headers, 'payMode', requiredText_(request.payMode, 'Payment mode'));
  setField_(sheet, rowIndex, headers, 'entryBy', requiredText_(request.entryBy, 'Entry by'));
  return { status: 'success' };
}

function deleteAmount_(request) {
  const sheet = getSpreadsheet_().getSheetByName('Amount');
  if (!sheet) throw new Error('Missing sheet: Amount. Run setupAccountPortal.');
  const rowIndex = Number(request.rowIndex);
  if (
    !Number.isInteger(rowIndex) ||
    rowIndex < 2 ||
    rowIndex > sheet.getLastRow()
  ) {
    throw new Error('Invalid ledger row.');
  }
  sheet.deleteRow(rowIndex);
  return { status: 'success' };
}

function parseDateField_(value, label) {
  const dateText = requiredText_(value, label);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateText)) {
    throw new Error(`${label} must use YYYY-MM-DD format.`);
  }
  const date = new Date(`${dateText}T00:00:00Z`);
  if (
    Number.isNaN(date.getTime()) ||
    Utilities.formatDate(date, 'UTC', 'yyyy-MM-dd') !== dateText
  ) {
    throw new Error(`Enter a valid ${label.toLowerCase()}.`);
  }
  return dateText;
}

function readAmount_() {
  return readRecords_('Amount').map((record) => ({
    ...record,
    date: formatDate_(record.date),
  }));
}

const DEPOSIT_CADENCES = Object.freeze({
  FD: ['monthly'],
  RD: ['weekly', 'monthly'],
  DRD: ['daily', 'weekly', 'monthly'],
});
const MAX_DEPOSIT_TENURE_MONTHS = 120;

function validDepositProduct_(value) {
  const product = String(value || '').toUpperCase();
  if (!Object.prototype.hasOwnProperty.call(DEPOSIT_CADENCES, product)) {
    throw new Error('Select a valid deposit product.');
  }
  return product;
}

function validDepositCadence_(value) {
  const cadence = String(value || '').toLowerCase();
  if (!['daily', 'weekly', 'monthly'].includes(cadence)) {
    throw new Error('Select a valid deposit frequency.');
  }
  return cadence;
}

function validateDepositProductCadence_(productValue, cadenceValue) {
  const product = validDepositProduct_(productValue);
  const cadence = validDepositCadence_(cadenceValue);
  if (!DEPOSIT_CADENCES[product].includes(cadence)) {
    throw new Error(`${product} is not available with ${cadence} payments.`);
  }
  return { product, cadence };
}

function depositMaturityDate_(startDate, tenureMonths) {
  const [year, month, day] = startDate.split('-').map(Number);
  const targetMonth = month - 1 + tenureMonths;
  const targetYear = year + Math.floor(targetMonth / 12);
  const targetMonthIndex = targetMonth % 12;
  const lastDay = new Date(Date.UTC(targetYear, targetMonthIndex + 1, 0)).getUTCDate();
  const maturity = new Date(
    Date.UTC(targetYear, targetMonthIndex, Math.min(day, lastDay)),
  );
  return Utilities.formatDate(maturity, 'UTC', 'yyyy-MM-dd');
}

function depositPeriodDates_(startDate, maturityDate, cadence) {
  const start = new Date(`${startDate}T00:00:00Z`);
  const maturity = new Date(`${maturityDate}T00:00:00Z`);
  const dates = [];
  if (cadence === 'monthly') {
    const startDay = start.getUTCDate();
    for (let period = 1; period <= MAX_DEPOSIT_TENURE_MONTHS; period++) {
      const targetMonth = start.getUTCMonth() + period;
      const targetYear = start.getUTCFullYear() + Math.floor(targetMonth / 12);
      const targetMonthIndex = targetMonth % 12;
      const lastDay = new Date(
        Date.UTC(targetYear, targetMonthIndex + 1, 0),
      ).getUTCDate();
      const dueDate = new Date(
        Date.UTC(targetYear, targetMonthIndex, Math.min(startDay, lastDay)),
      );
      if (dueDate > maturity) break;
      dates.push(Utilities.formatDate(dueDate, 'UTC', 'yyyy-MM-dd'));
    }
    return dates;
  }

  const daysPerPeriod = cadence === 'weekly' ? 7 : 1;
  for (
    let dueDate = new Date(start.getTime() + daysPerPeriod * 86400000);
    dueDate <= maturity;
    dueDate = new Date(dueDate.getTime() + daysPerPeriod * 86400000)
  ) {
    dates.push(Utilities.formatDate(dueDate, 'UTC', 'yyyy-MM-dd'));
  }
  return dates;
}

function calculateDepositMaturity_(
  product,
  cadence,
  amount,
  annualRate,
  tenureMonths,
  periodCount,
) {
  const rate = annualRate / 100;
  if (product === 'FD') {
    return roundCurrency_(amount * Math.pow(1 + rate / 12, tenureMonths));
  }
  const periodsPerYear =
    cadence === 'daily' ? 365 : cadence === 'weekly' ? 52 : 12;
  const periodRate = rate / periodsPerYear;
  const maturity =
    periodRate === 0
      ? amount * periodCount
      : amount * (Math.pow(1 + periodRate, periodCount) - 1) / periodRate;
  return roundCurrency_(maturity);
}

function roundCurrency_(value) {
  if (!Number.isFinite(value)) throw new Error('Maturity amount is too large.');
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function depositAccountInput_(request) {
  const { product, cadence } = validateDepositProductCadence_(
    request.product,
    request.cadence,
  );
  const memberName = cleanText_(request.memberName, CONFIG.maxNameLength);
  if (!memberName) throw new Error('Member name is required.');
  const startDate = parseDateField_(request.startDate, 'Start date');
  const amount = parseNonNegativeNumber_(
    request.amount,
    product === 'FD' ? 'Principal amount' : 'Installment amount',
  );
  if (amount <= 0) throw new Error('Amount must be greater than zero.');
  const annualRate = parseNonNegativeNumber_(
    request.annualRate,
    'Annual interest rate',
  );
  if (annualRate > 100) {
    throw new Error('Annual interest rate cannot exceed 100%.');
  }
  const tenureMonths = Number(request.tenureMonths);
  if (
    !Number.isInteger(tenureMonths) ||
    tenureMonths < 1 ||
    tenureMonths > MAX_DEPOSIT_TENURE_MONTHS
  ) {
    throw new Error(
      `Tenure must be between 1 and ${MAX_DEPOSIT_TENURE_MONTHS} months.`,
    );
  }
  const maturityDate = depositMaturityDate_(startDate, tenureMonths);
  const periodDates =
    product === 'FD'
      ? []
      : depositPeriodDates_(startDate, maturityDate, cadence);
  const payments = periodDates.map(() => false);
  const maturityAmount = calculateDepositMaturity_(
    product,
    cadence,
    amount,
    annualRate,
    tenureMonths,
    periodDates.length,
  );
  return {
    memberName,
    product,
    cadence,
    startDate,
    amount,
    annualRate,
    tenureMonths,
    maturityDate,
    maturityAmount,
    payments,
    periodDates,
  };
}

function addDepositAccount_(request, user) {
  const input = depositAccountInput_(request);
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  if (!sheet) {
    throw new Error('Deposit_Accounts sheet is missing. Run setupAccountPortal.');
  }
  appendRecord_(sheet, getHeaders_(sheet), {
    id: Utilities.getUuid(),
    ...input,
    payments: JSON.stringify(input.payments),
    createdAt: new Date(),
    createdBy: user.id,
  });
  return { status: 'success' };
}

function editDepositAccount_(request) {
  const id = requiredText_(request.id, 'Deposit account ID');
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  if (!sheet) {
    throw new Error('Deposit_Accounts sheet is missing. Run setupAccountPortal.');
  }
  const rowIndex = depositAccountRow_(id, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');

  const headers = getHeaders_(sheet);
  const existing = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const input = depositAccountInput_(request);
  if (
    existing.product !== input.product ||
    existing.cadence !== input.cadence
  ) {
    throw new Error('A deposit account product and cadence cannot be changed.');
  }

  const oldStartDate = formatDate_(existing.startDate);
  const oldMaturityDate = formatDate_(existing.maturityDate);
  const oldDates =
    input.product === 'FD'
      ? []
      : depositPeriodDates_(oldStartDate, oldMaturityDate, input.cadence);
  let oldPayments;
  try {
    oldPayments = JSON.parse(String(existing.payments || '[]'));
  } catch (error) {
    console.error(`Invalid payment schedule for deposit ${id}.`, error);
    throw new Error('The deposit payment schedule is invalid.');
  }
  const newDates =
    input.product === 'FD'
      ? []
      : depositPeriodDates_(input.startDate, input.maturityDate, input.cadence);
  const payments = preserveDepositPayments_(oldPayments, oldDates, newDates);
  const updated = Object.assign({}, existing, input, {
    id,
    payments: JSON.stringify(payments),
  });
  sheet
    .getRange(rowIndex, 1, 1, headers.length)
    .setValues([
      headers.map((header) =>
        Object.prototype.hasOwnProperty.call(updated, header)
          ? safeCellValue_(updated[header])
          : '',
      ),
    ]);
  return { status: 'success' };
}

function preserveDepositPayments_(payments, oldDates, newDates) {
  if (
    !Array.isArray(payments) ||
    payments.length !== oldDates.length ||
    payments.some((paid) => typeof paid !== 'boolean')
  ) {
    throw new Error('The deposit payment schedule is invalid.');
  }
  const paidDates = new Set(
    oldDates.filter((date, index) => payments[index]),
  );
  const newDateSet = new Set(newDates);
  if ([...paidDates].some((date) => !newDateSet.has(date))) {
    throw new Error(
      'This edit would remove a paid installment date. Keep the existing paid dates in the schedule.',
    );
  }
  const paymentsByDate = new Map(
    oldDates.map((date, index) => [date, payments[index]]),
  );
  return newDates.map((date) => paymentsByDate.get(date) === true);
}

function readDepositAccounts_(productValue, cadence, user) {
  const { product, cadence: validCadence } = validateDepositProductCadence_(
    productValue,
    cadence,
  );
  const memberName = normalizeMemberName_(user.name);
  return readRecords_('Deposit_Accounts')
    .filter(
      (record) =>
        record.product === product &&
        record.cadence === validCadence &&
        (user.role !== 'Member' ||
          normalizeMemberName_(record.memberName) === memberName),
    )
    .map((record) => {
      let payments;
      try {
        payments = JSON.parse(String(record.payments || '[]'));
      } catch (error) {
        console.error(`Invalid payment schedule for deposit ${record.id}.`, error);
        throw new Error('A deposit payment schedule is invalid. Contact an administrator.');
      }
      if (
        !Array.isArray(payments) ||
        payments.some((paid) => typeof paid !== 'boolean')
      ) {
        throw new Error('A deposit payment schedule is invalid. Contact an administrator.');
      }
      const startDate = formatDate_(record.startDate);
      const maturityDate = formatDate_(record.maturityDate);
      const periodDates =
        product === 'FD'
          ? []
          : depositPeriodDates_(startDate, maturityDate, validCadence);
      if (payments.length !== periodDates.length) {
        throw new Error('A deposit payment schedule is invalid. Contact an administrator.');
      }
      return {
        id: String(record.id || ''),
        memberName: String(record.memberName || ''),
        product,
        cadence: validCadence,
        startDate,
        amount: Number(record.amount) || 0,
        annualRate: Number(record.annualRate) || 0,
        tenureMonths: Number(record.tenureMonths) || 0,
        maturityDate,
        maturityAmount: Number(record.maturityAmount) || 0,
        payments,
        periodDates,
      };
    });
}

function depositAccountRow_(id, sheet) {
  const headers = getHeaders_(sheet);
  const idColumn = headers.indexOf('id') + 1;
  if (idColumn < 1 || sheet.getLastRow() < 2) return 0;
  const values = sheet
    .getRange(2, idColumn, sheet.getLastRow() - 1, 1)
    .getValues();
  const index = values.findIndex((row) => String(row[0]) === String(id));
  return index < 0 ? 0 : index + 2;
}

function toggleDepositPayment_(request) {
  const id = requiredText_(request.id, 'Deposit account ID');
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  const rowIndex = depositAccountRow_(id, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');
  const headers = getHeaders_(sheet);
  const row = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  if (row.product === 'FD') {
    throw new Error('Fixed deposits do not have recurring payment periods.');
  }
  const { product, cadence } = validateDepositProductCadence_(
    row.product,
    row.cadence,
  );
  const periodIndex = Number(request.periodIndex);
  const periodDates = depositPeriodDates_(
    formatDate_(row.startDate),
    formatDate_(row.maturityDate),
    cadence,
  );
  if (
    !Number.isInteger(periodIndex) ||
    periodIndex < 1 ||
    periodIndex > periodDates.length
  ) {
    throw new Error('Invalid deposit payment period.');
  }
  let payments;
  try {
    payments = JSON.parse(String(row.payments || '[]'));
  } catch (error) {
    console.error(`Invalid payment schedule for deposit ${id}.`, error);
    throw new Error('The deposit payment schedule is invalid.');
  }
  if (
    !Array.isArray(payments) ||
    payments.length !== periodDates.length ||
    payments.some((paid) => typeof paid !== 'boolean')
  ) {
    throw new Error('The deposit payment schedule is invalid.');
  }
  payments[periodIndex - 1] = !payments[periodIndex - 1];
  setField_(sheet, rowIndex, headers, 'payments', JSON.stringify(payments));
  return { status: 'success', product, cadence };
}

function deleteDepositAccount_(request) {
  const id = requiredText_(request.id, 'Deposit account ID');
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  const rowIndex = depositAccountRow_(id, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');
  sheet.deleteRow(rowIndex);
  return { status: 'success' };
}

function addCollection_(request) {
  const sheetName = String(request.sheetName || '');
  if (
    !['Daily_Collection', 'Weekly_Collection', 'Monthly_Collection'].includes(
      sheetName,
    )
  ) {
    throw new Error('Invalid collection sheet.');
  }
  const memberName = cleanText_(request.memberName, CONFIG.maxNameLength);
  if (!memberName) throw new Error('Member name is required.');

  const date = parseDateField_(request.date, 'Start date');

  const depAmt = parseNonNegativeNumber_(request.depAmt, 'Collection amount');
  if (depAmt <= 0) {
    throw new Error('Collection amount must be greater than zero.');
  }
  const sheet = getSpreadsheet_().getSheetByName(sheetName);
  const headers = getHeaders_(sheet);
  const periodHeaders = headers.filter((header) => /^P\d+$/i.test(header));
  if (periodHeaders.length < 1) {
    throw new Error(`No payment periods are configured in ${sheetName}.`);
  }
  const requestedPeriods = request.periods;
  if (
    requestedPeriods !== undefined &&
    (!Array.isArray(requestedPeriods) ||
      requestedPeriods.length !== periodHeaders.length ||
      requestedPeriods.some((isPaid) => typeof isPaid !== 'boolean'))
  ) {
    throw new Error('Payment schedule does not match the configured periods.');
  }
  const periods =
    requestedPeriods || periodHeaders.map(() => false);
  const paidCount = periods.filter(Boolean).length;
  appendRecord_(sheet, headers, {
    memberName,
    date,
    depAmt,
    totalCount: paidCount,
    totalReceived: paidCount * depAmt,
    grandTotal: 0,
    ...Object.fromEntries(
      periodHeaders.map((header, index) => [header, periods[index]]),
    ),
  });
  return { status: 'success' };
}

function editCollection_(request) {
  const sheetName = validCollectionSheetName_(request.sheetName);
  const sheet = getSpreadsheet_().getSheetByName(sheetName);
  const headers = getHeaders_(sheet);
  const rowIndex = collectionRowIndex_(request.rowIndex, sheet);
  const memberName = cleanText_(request.memberName, CONFIG.maxNameLength);
  if (!memberName) throw new Error('Member name is required.');
  const date = parseCollectionDate_(request.date);
  const depAmt = parseNonNegativeNumber_(request.depAmt, 'Collection amount');
  if (depAmt <= 0) {
    throw new Error('Collection amount must be greater than zero.');
  }
  const periods = headers
    .map((header, index) => ({ header, column: index + 1 }))
    .filter((entry) => /^P\d+$/i.test(entry.header));
  if (periods.length < 1) {
    throw new Error(`No payment periods are configured in ${sheetName}.`);
  }
  const paidCount = periods
    .map((period) => isPaid_(sheet.getRange(rowIndex, period.column).getValue()))
    .filter(Boolean).length;

  setField_(sheet, rowIndex, headers, 'memberName', memberName);
  setField_(sheet, rowIndex, headers, 'date', date);
  setField_(sheet, rowIndex, headers, 'depAmt', depAmt);
  setField_(sheet, rowIndex, headers, 'totalCount', paidCount);
  setField_(sheet, rowIndex, headers, 'totalReceived', paidCount * depAmt);
  return { status: 'success' };
}

function deleteCollection_(request) {
  const sheet = getSpreadsheet_().getSheetByName(
    validCollectionSheetName_(request.sheetName),
  );
  const rowIndex = collectionRowIndex_(request.rowIndex, sheet);
  sheet.deleteRow(rowIndex);
  return { status: 'success' };
}

function validCollectionSheetName_(value) {
  const sheetName = String(value || '');
  if (
    !['Daily_Collection', 'Weekly_Collection', 'Monthly_Collection'].includes(
      sheetName,
    )
  ) {
    throw new Error('Invalid collection sheet.');
  }
  return sheetName;
}

function collectionRowIndex_(value, sheet) {
  const rowIndex = Number(value);
  if (
    !Number.isInteger(rowIndex) ||
    rowIndex < 2 ||
    rowIndex > sheet.getLastRow()
  ) {
    throw new Error('Invalid collection row.');
  }
  return rowIndex;
}

function parseCollectionDate_(value) {
  return parseDateField_(value, 'Start date');
}

function readCollection_(sheetName) {
  const sheet = getSpreadsheet_().getSheetByName(sheetName);
  const headers = getHeaders_(sheet);
  return readRecords_(sheetName).map((record) => {
    const periods = headers
      .filter((header) => /^P\d+$/i.test(header))
      .map((header) => isPaid_(record[header]));
    const paidCount = periods.filter(Boolean).length;
    const amount = Number(record.depAmt) || 0;
    return {
      memberName: record.memberName || '',
      date: formatDate_(record.date),
      depAmt: amount,
      totalCount: paidCount,
      totalReceived: paidCount * amount,
      grandTotal: Number(record.grandTotal) || 0,
      periods,
      rowIndex: record.__rowIndex,
    };
  });
}

function readCollectionForUser_(sheetName, user) {
  const records = readCollection_(sheetName);
  const permissions = permissionsForUser_(user);
  if (user.role === 'Member') {
    if (!permissions.own_collection_read) {
      throw new Error('You do not have permission to view collection data.');
    }
    const memberName = normalizeMemberName_(user.name);
    if (!memberName) {
      throw new Error('Your account name is missing. Contact an administrator.');
    }
    const matchingMembers = readRecords_('Users').filter(
      (record) =>
        isActive_(record.active) &&
        record.role === 'Member' &&
        normalizeMemberName_(record.name) === memberName,
    );
    if (matchingMembers.length !== 1) {
      throw new Error(
        'Your account name is not unique. Contact an administrator to update it.',
      );
    }
    return records.filter(
      (record) => normalizeMemberName_(record.memberName) === memberName,
    );
  }
  if (
    user.role === 'Admin' ||
    permissions.shared_data_read ||
    permissions.collection_manage
  ) {
    return records;
  }
  if (!permissions.own_collection_read) {
    throw new Error('You do not have permission to view collection data.');
  }
  return records;
}

function toggleCollection_(request) {
  const sheetName = String(request.sheetName || '');
  if (
    !['Daily_Collection', 'Weekly_Collection', 'Monthly_Collection'].includes(
      sheetName,
    )
  ) {
    throw new Error('Invalid collection sheet.');
  }
  const rowIndex = Number(request.rowIndex);
  const periodIndex = Number(request.periodIndex);
  const sheet = getSpreadsheet_().getSheetByName(sheetName);
  const headers = getHeaders_(sheet);
  if (
    !Number.isInteger(rowIndex) ||
    rowIndex < 2 ||
    rowIndex > sheet.getLastRow()
  ) {
    throw new Error('Invalid collection row.');
  }
  if (!Number.isInteger(periodIndex) || periodIndex < 1) {
    throw new Error('Invalid collection period.');
  }
  const periodColumn = headers.indexOf(`P${periodIndex}`) + 1;
  if (periodColumn < 1) throw new Error('Invalid collection period.');
  const row = sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0];
  row[periodColumn - 1] = !isPaid_(row[periodColumn - 1]);

  const periodColumns = headers
    .map((header, index) => /^P\d+$/i.test(header) ? index : -1)
    .filter((index) => index >= 0);
  const count = periodColumns
    .map((index) => isPaid_(row[index]))
    .filter(Boolean).length;
  const amountColumn = headers.indexOf('depAmt');
  const countColumn = headers.indexOf('totalCount');
  const receivedColumn = headers.indexOf('totalReceived');
  if (amountColumn < 0 || countColumn < 0 || receivedColumn < 0) {
    throw new Error('Collection sheet is missing payment summary columns.');
  }
  const amount = Number(row[amountColumn]) || 0;
  row[countColumn] = count;
  row[receivedColumn] = count * amount;
  sheet.getRange(rowIndex, 1, 1, headers.length).setValues([row]);
  return { status: 'success' };
}

function createUser_(user) {
  const sheet = getSpreadsheet_().getSheetByName('Users');
  if (!sheet) throw new Error('Users sheet is missing. Run setupAccountPortal.');
  const headers = getHeaders_(sheet);
  const salt = Utilities.getUuid();
  const id = Utilities.getUuid();
  const accountNo = nextAccountNumber_(user.role);
  const profileImageFileId = user.profileImageData
    ? saveProfileImage_(
        user.profileImageData,
        user.profileImageMimeType,
        id,
      )
    : '';
  try {
    appendRecord_(sheet, headers, {
      id,
      accountNo,
      name: user.name,
      profileImageUrl: '',
      profileImageFileId,
      email: user.email,
      role: user.role,
      passwordSalt: salt,
      passwordHash: passwordHash_(user.password, salt, getPasswordPepper_()),
      active: true,
      dailyAccess: user.dailyAccess !== false,
      weeklyAccess: user.weeklyAccess !== false,
      monthlyAccess: user.monthlyAccess !== false,
      createdAt: new Date(),
    });
  } catch (error) {
    if (profileImageFileId) trashProfileImage_(profileImageFileId);
    throw error;
  }
  return id;
}

function getOrCreateProfileImagesFolder_() {
  const properties = PropertiesService.getScriptProperties();
  const folderId = properties.getProperty('PROFILE_IMAGES_FOLDER_ID');
  if (folderId) return DriveApp.getFolderById(folderId);
  const folder = DriveApp.createFolder('NTCCSL Portal Profile Images');
  properties.setProperty('PROFILE_IMAGES_FOLDER_ID', folder.getId());
  return folder;
}

function saveProfileImage_(encodedImage, mimeType, userId) {
  if (typeof encodedImage !== 'string' || !encodedImage) {
    throw new Error('Select a profile image to upload.');
  }
  if (
    mimeType !== 'image/jpeg' &&
    mimeType !== 'image/png' &&
    mimeType !== 'image/webp'
  ) {
    throw new Error('Profile images must be JPEG, PNG, or WebP.');
  }
  const maximumEncodedLength =
    Math.ceil(CONFIG.maxProfileImageBytes / 3) * 4;
  if (encodedImage.length > maximumEncodedLength) {
    throw new Error('Profile image is too large. Choose an image under 300 KB.');
  }
  let bytes;
  try {
    bytes = Utilities.base64Decode(encodedImage);
  } catch (error) {
    throw new Error('Profile image data is invalid.');
  }
  if (bytes.length === 0 || bytes.length > CONFIG.maxProfileImageBytes) {
    throw new Error('Profile image must be between 1 byte and 300 KB.');
  }
  validateProfileImageSignature_(bytes, mimeType);
  const extension = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  }[mimeType];
  const blob = Utilities.newBlob(bytes, mimeType, `profile-${userId}.${extension}`);
  return getOrCreateProfileImagesFolder_().createFile(blob).getId();
}

function validateProfileImageSignature_(bytes, mimeType) {
  const byteAt = (index) => bytes[index] & 0xff;
  let valid = false;
  if (mimeType === 'image/jpeg') {
    valid =
      bytes.length >= 3 &&
      byteAt(0) === 0xff &&
      byteAt(1) === 0xd8 &&
      byteAt(2) === 0xff;
  } else if (mimeType === 'image/png') {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    valid =
      bytes.length >= signature.length &&
      signature.every((value, index) => byteAt(index) === value);
  } else if (mimeType === 'image/webp') {
    valid =
      bytes.length >= 12 &&
      byteAt(0) === 0x52 &&
      byteAt(1) === 0x49 &&
      byteAt(2) === 0x46 &&
      byteAt(3) === 0x46 &&
      byteAt(8) === 0x57 &&
      byteAt(9) === 0x45 &&
      byteAt(10) === 0x42 &&
      byteAt(11) === 0x50;
  }
  if (!valid) {
    throw new Error('Profile image data does not match its image type.');
  }
}

function trashProfileImage_(fileId) {
  DriveApp.getFileById(String(fileId)).setTrashed(true);
}

function profileImageDataUrl_(user) {
  const fileId = String(user.profileImageFileId || '');
  if (!fileId) return String(user.profileImageUrl || '');
  const blob = DriveApp.getFileById(fileId).getBlob();
  const mimeType = blob.getContentType();
  if (
    mimeType !== 'image/jpeg' &&
    mimeType !== 'image/png' &&
    mimeType !== 'image/webp'
  ) {
    throw new Error('Stored profile image has an unsupported file type.');
  }
  return `data:${mimeType};base64,${Utilities.base64Encode(blob.getBytes())}`;
}

function nextAccountNumber_(role) {
  const prefix = accountNumberPrefix_(role);
  if (role === 'Admin') {
    const existingNumbers = new Set(
      readRecords_('Users').map((user) => String(user.accountNo || '')),
    );
    let accountNo;
    do {
      accountNo = `ADM${Math.floor(100000000 + Math.random() * 900000000)}`;
    } while (existingNumbers.has(accountNo));
    return accountNo;
  }

  const highest = readRecords_('Users').reduce((max, user) => {
    const match = String(user.accountNo || '').match(
      new RegExp(`^${prefix}(\\d{9})$`),
    );
    const value = match ? Number(match[1]) : 0;
    return Number.isSafeInteger(value) && value > max ? value : max;
  }, 0);
  if (highest >= 999999999) {
    throw new Error(`No ${role} account numbers remain.`);
  }
  return `${prefix}${String(highest + 1).padStart(9, '0')}`;
}

function accountNumberPrefix_(role) {
  if (role === 'Member') return 'DRD';
  if (role === 'Collector') return 'EMP';
  if (role === 'Admin') return 'ADM';
  throw new Error(`Cannot create an account number for role ${role}.`);
}

function backfillAccountNumbers_() {
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const accountNoColumn = headers.indexOf('accountNo') + 1;
  if (accountNoColumn < 1 || sheet.getLastRow() < 2) return;

  const users = readRecords_('Users');
  const validAccountNumber = (user) => {
    const prefix = accountNumberPrefix_(String(user.role || ''));
    return new RegExp(`^${prefix}\\d{9}$`).test(
      String(user.accountNo || ''),
    );
  };
  users.forEach((user) => {
    if (!validAccountNumber(user)) {
      setField_(
        sheet,
        user.__rowIndex,
        headers,
        'accountNo',
        nextAccountNumber_(String(user.role || '')),
      );
    }
  });
}

function requireRole_(token, allowedRoles) {
  const session = CacheService.getScriptCache().get(
    `session:${sha256Hex_(String(token || ''))}`,
  );
  if (!session) throw new Error('Your session expired. Sign in again.');
  const stored = JSON.parse(session);
  const user = findUserById_(stored.userId);
  if (!user || !isActive_(user.active)) {
    throw new Error('This account is inactive. Contact an administrator.');
  }
  if (!allowedRoles.includes(user.role)) {
    throw new Error('You do not have permission to perform this action.');
  }
  return user;
}

function requirePermission_(token, permission) {
  const user = requireRole_(token, PORTAL_ROLES);
  if (
    user.role !== 'Admin' &&
    !permissionsForUser_(user)[permission]
  ) {
    throw new Error('You do not have permission to perform this action.');
  }
  return user;
}

function requireAnyPermission_(token, permissions) {
  const user = requireRole_(token, PORTAL_ROLES);
  if (
    user.role !== 'Admin' &&
    !permissions.some((permission) => permissionsForUser_(user)[permission])
  ) {
    throw new Error('You do not have permission to view this data.');
  }
  return user;
}

function requireCollectionRead_(token, reportAccessField) {
  const user = requireRole_(token, PORTAL_ROLES);
  if (
    user.role === 'Member' &&
    !isReportAccessEnabled_(user[reportAccessField])
  ) {
    throw new Error('This report is inactive for your account.');
  }
  const permissions = permissionsForUser_(user);
  if (
    user.role !== 'Admin' &&
    !permissions.shared_data_read &&
    !permissions.own_collection_read &&
    !permissions.collection_manage
  ) {
    throw new Error('You do not have permission to view collection data.');
  }
  return user;
}

function requireDepositRead_(token, cadence) {
  const user = requireRole_(token, PORTAL_ROLES);
  const reportAccessField = `${cadence}Access`;
  if (
    user.role === 'Member' &&
    !isReportAccessEnabled_(user[reportAccessField])
  ) {
    throw new Error('This report is inactive for your account.');
  }
  const permissions = permissionsForUser_(user);
  if (
    user.role !== 'Admin' &&
    !permissions.deposit_view &&
    !permissions.deposit_manage
  ) {
    throw new Error('You do not have permission to view deposit accounts.');
  }
  return user;
}

function findUserByEmail_(email) {
  return readRecords_('Users').find(
    (user) => normalizeEmail_(user.email) === email,
  );
}

function findUserById_(id) {
  return readRecords_('Users').find((user) => String(user.id) === String(id));
}

function findUserRowById_(id) {
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const idColumn = headers.indexOf('id') + 1;
  if (idColumn < 1 || sheet.getLastRow() < 2) return 0;
  const found = sheet
    .getRange(2, idColumn, sheet.getLastRow() - 1, 1)
    .createTextFinder(String(id))
    .matchEntireCell(true)
    .findNext();
  return found ? found.getRow() : 0;
}

function assertAnotherActiveAdmin_(exceptId) {
  const admins = readRecords_('Users').filter(
    (user) =>
      String(user.id) !== String(exceptId) &&
      user.role === 'Admin' &&
      isActive_(user.active),
  );
  if (admins.length === 0) {
    throw new Error('The last active admin cannot be deleted or demoted.');
  }
}

function readRecords_(sheetName) {
  const sheet = getSpreadsheet_().getSheetByName(sheetName);
  if (!sheet) {
    throw new Error(`Missing sheet: ${sheetName}. Run setupAccountPortal.`);
  }
  const headers = getHeaders_(sheet);
  if (sheet.getLastRow() < 2) return [];
  return sheet
    .getRange(2, 1, sheet.getLastRow() - 1, headers.length)
    .getValues()
    .map((row, index) => ({
      ...rowToObject_(headers, row),
      __rowIndex: index + 2,
    }))
    .filter((record) =>
      Object.keys(record).some(
        (key) => key !== '__rowIndex' && record[key] !== '',
      ),
    );
}

function appendRecord_(sheet, headers, record) {
  sheet.appendRow(
    headers.map((header) =>
      Object.prototype.hasOwnProperty.call(record, header)
        ? safeCellValue_(record[header])
        : '',
    ),
  );
}

function rowToObject_(headers, row) {
  const record = {};
  headers.forEach((header, index) => {
    record[header] = row[index];
  });
  return record;
}

function ensureHeaders_(sheet, requiredHeaders) {
  const lastColumn = sheet.getLastColumn();
  if (sheet.getLastRow() === 0 || lastColumn === 0) {
    sheet.getRange(1, 1, 1, requiredHeaders.length).setValues([requiredHeaders]);
    return;
  }
  const existing = sheet
    .getRange(1, 1, 1, lastColumn)
    .getValues()[0]
    .map((value) => String(value));
  const missing = requiredHeaders.filter((header) => !existing.includes(header));
  if (missing.length > 0) {
    sheet
      .getRange(1, lastColumn + 1, 1, missing.length)
      .setValues([missing]);
  }
}

function getHeaders_(sheet) {
  if (!sheet || sheet.getLastColumn() < 1) {
    throw new Error('Sheet is not configured. Run setupAccountPortal.');
  }
  return sheet
    .getRange(1, 1, 1, sheet.getLastColumn())
    .getValues()[0]
    .map((value) => String(value));
}

function setField_(sheet, row, headers, field, value) {
  const column = headers.indexOf(field) + 1;
  if (column < 1) throw new Error(`Missing sheet column: ${field}`);
  sheet.getRange(row, column).setValue(safeCellValue_(value));
}

function getSpreadsheet_() {
  const id =
    PropertiesService.getScriptProperties().getProperty('SPREADSHEET_ID');
  if (!id) {
    throw new Error('Spreadsheet is not configured. Run setupAccountPortal.');
  }
  return SpreadsheetApp.openById(id);
}

function getPasswordPepper_() {
  const pepper =
    PropertiesService.getScriptProperties().getProperty('PASSWORD_PEPPER');
  if (!pepper) {
    throw new Error('Password secret is missing. Run setupAccountPortal.');
  }
  return pepper;
}

function passwordHash_(password, salt, pepper) {
  return bytesToHex_(
    Utilities.computeHmacSha256Signature(
      `${salt}:${password}`,
      pepper,
      Utilities.Charset.UTF_8,
    ),
  );
}

function sha256Hex_(value) {
  return bytesToHex_(
    Utilities.computeDigest(
      Utilities.DigestAlgorithm.SHA_256,
      String(value),
      Utilities.Charset.UTF_8,
    ),
  );
}

function bytesToHex_(bytes) {
  return bytes.map((byte) => (byte + 256).toString(16).slice(-2)).join('');
}

function constantTimeEquals_(left, right) {
  const a = String(left || '');
  const b = String(right || '');
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    difference |= (a.charCodeAt(index) || 0) ^ (b.charCodeAt(index) || 0);
  }
  return difference === 0;
}

function validateRegistration_(name, email, password, minimumPasswordLength) {
  validateNameAndEmail_(name, email);
  validatePassword_(password, minimumPasswordLength);
}

function validateNameAndEmail_(name, email) {
  if (!name || name.length > CONFIG.maxNameLength) {
    throw new Error('Enter a valid name.');
  }
  if (
    !email ||
    email.length > CONFIG.maxEmailLength ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new Error('Enter a valid email address.');
  }
}

function assertUniqueMemberName_(name, exceptUserId) {
  const normalizedName = normalizeMemberName_(name);
  const duplicate = readRecords_('Users').some(
    (user) =>
      isActive_(user.active) &&
      user.role === 'Member' &&
      String(user.id) !== String(exceptUserId || '') &&
      normalizeMemberName_(user.name) === normalizedName,
  );
  if (duplicate) {
    throw new Error(
      'An active Member account already uses this name. Member names must be unique.',
    );
  }
}

function validatePassword_(password, minimumLength) {
  if (
    password.length < minimumLength ||
    password.length > CONFIG.maxPasswordLength
  ) {
    throw new Error(
      `Password must be between ${minimumLength} and ${CONFIG.maxPasswordLength} characters.`,
    );
  }
}

function normalizeEmail_(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeMemberName_(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

function normalizeRole_(value) {
  const role = String(value || '').trim();
  if (!['Admin', 'Collector', 'Member'].includes(role)) {
    throw new Error('Role must be Admin, Collector, or Member.');
  }
  return role;
}

function cleanText_(value, maxLength) {
  const text = String(value || '').trim();
  if (text.length > maxLength) throw new Error('A text field is too long.');
  return text;
}

function requiredText_(value, label) {
  const text = String(value || '').trim();
  if (!text) throw new Error(`${label} is required.`);
  return text;
}

function parseNonNegativeNumber_(value, label) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    throw new Error(`${label} must be a non-negative number.`);
  }
  return number;
}

function isActive_(value) {
  return value === true || String(value).toLowerCase() === 'true';
}

function isPaid_(value) {
  return value === true || value === 1 || String(value).toLowerCase() === 'true';
}

function publicUser_(user) {
  return {
    id: String(user.id),
    accountNo: String(user.accountNo || ''),
    name: String(user.name || ''),
    profileImageUrl: profileImageDataUrl_(user),
    email: String(user.email || ''),
    role: String(user.role || 'Member'),
    dailyAccess: isReportAccessEnabled_(user.dailyAccess),
    weeklyAccess: isReportAccessEnabled_(user.weeklyAccess),
    monthlyAccess: isReportAccessEnabled_(user.monthlyAccess),
  };
}

function formatDate_(value) {
  if (value instanceof Date) {
    const spreadsheet = getSpreadsheet_();
    const timeZone =
      spreadsheet.getSpreadsheetTimeZone() || Session.getScriptTimeZone();
    return Utilities.formatDate(value, timeZone, 'yyyy-MM-dd');
  }
  const text = String(value || '').trim();
  if (!text) return '';
  const isoDate = text.match(/^(\d{4}-\d{2}-\d{2})(?:$|T)/);
  return isoDate ? isoDate[1] : text;
}

function safeCellValue_(value) {
  if (typeof value !== 'string') return value;
  return /^[=+\-@]/.test(value) ? `'${value}` : value;
}

function withScriptLock_(callback) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) {
    throw new Error('The service is busy. Please try again.');
  }
  try {
    return callback();
  } finally {
    lock.releaseLock();
  }
}

function jsonOutput_(data) {
  return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(
    ContentService.MimeType.JSON,
  );
}

function safeErrorMessage_(error) {
  const message = error && error.message ? String(error.message) : '';
  return message || 'The request could not be completed.';
}