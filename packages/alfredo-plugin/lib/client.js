window.__ModuleLoader__.load({ id: 'alfredo-plugin', factory: (require) => {
var module = { exports: {} };
var exports = module.exports;
const React = require('react');
const { createRoot } = require('react-dom/client');

const COLUMNS = [
  ['BACKLOG', 'Backlog'],
  ['READY', 'Ready (CLI derived)'],
  ['CLAIMED', 'Claimed / Doing'],
  ['VERIFYING', 'Verifying'],
  ['BLOCKED', 'Blocked'],
  ['DONE', 'Done'],
];

function AlfredoView() {
  const [tasks, setTasks] = React.useState([]);
  const [readyTasks, setReadyTasks] = React.useState([]);
  const [sessions, setSessions] = React.useState([]);
  const [packages, setPackages] = React.useState([]);
  const [activeTab, setActiveTab] = React.useState('kanban'); // 'kanban', 'workers', 'packages'
  
  const [page, setPage] = React.useState(0);
  const [showCancelled, setShowCancelled] = React.useState(false);
  const [searchFilter, setSearchFilter] = React.useState('');
  const pageSize = 50;

  // Drawer / Modal states
  const [showCreateModal, setShowCreateModal] = React.useState(false);
  const [selectedTask, setSelectedTask] = React.useState(null);
  const [taskEvents, setTaskEvents] = React.useState([]);
  
  // Create task form state
  const [newTitle, setNewTitle] = React.useState('');
  const [newPriority, setNewPriority] = React.useState('normal');
  const [newTrack, setNewTrack] = React.useState('');
  const [newRun, setNewRun] = React.useState('');
  const [newDeps, setNewDeps] = React.useState('');
  const [newAcceptance, setNewAcceptance] = React.useState('');
  const [newTopics, setNewTopics] = React.useState('');
  const [newFiles, setNewFiles] = React.useState('');
  const [actionMessage, setActionMessage] = React.useState('');

  // Worker form state
  const [workerAdapter, setWorkerAdapter] = React.useState('codex');
  const [workerAgent, setWorkerAgent] = React.useState('executor');

  // Package target state
  const [pkgTarget, setPkgTarget] = React.useState('dsh');
  const [pkgScope, setPkgScope] = React.useState('user');

  const loadData = React.useCallback(async () => {
    try {
      const [tRes, rRes, sRes, pRes] = await Promise.all([
        fetch('/api/alfredo/tasks').catch(() => null),
        fetch('/api/alfredo/ready').catch(() => null),
        fetch('/api/alfredo/sessions').catch(() => null),
        fetch('/api/alfredo/packages').catch(() => null),
      ]);
      if (tRes && tRes.ok) {
        const val = await tRes.json();
        setTasks(Array.isArray(val) ? val : val.tasks || []);
      }
      if (rRes && rRes.ok) {
        const val = await rRes.json();
        setReadyTasks(Array.isArray(val) ? val : val.tasks || []);
      }
      if (sRes && sRes.ok) {
        const val = await sRes.json();
        setSessions(Array.isArray(val) ? val : []);
      }
      if (pRes && pRes.ok) {
        const val = await pRes.json();
        setPackages(Array.isArray(val) ? val : []);
      }
    } catch (e) {
      console.error('Failed to load alfredo data', e);
    }
  }, []);

  React.useEffect(() => {
    loadData();
    const timer = setInterval(loadData, 2000);
    return () => clearInterval(timer);
  }, [loadData]);

  // Load task events when a task is selected
  React.useEffect(() => {
    if (!selectedTask) {
      setTaskEvents([]);
      return;
    }
    let active = true;
    const loadEvents = async () => {
      try {
        const res = await fetch(`/api/alfredo/task-events?task=${selectedTask.id}`);
        if (res.ok) {
          const val = await res.json();
          if (active) setTaskEvents(Array.isArray(val) ? val : []);
        }
      } catch (_) {
        if (active) setTaskEvents([]);
      }
    };
    loadEvents();
    return () => { active = false; };
  }, [selectedTask]);

  const handleCreateTask = async (e) => {
    e.preventDefault();
    if (!newTitle.trim()) return;
    try {
      const payload = {
        title: newTitle.trim(),
        priority: newPriority,
        track: newTrack.trim() || undefined,
        run: newRun.trim() || undefined,
        dependencies: newDeps ? newDeps.split(',').map(s => s.trim()).filter(Boolean) : [],
        acceptance: newAcceptance ? newAcceptance.split('\n').map(s => s.trim()).filter(Boolean) : [],
        topics: newTopics ? newTopics.split(',').map(s => s.trim()).filter(Boolean) : [],
        files: newFiles ? newFiles.split(',').map(s => s.trim()).filter(Boolean) : [],
      };
      const res = await fetch('/api/alfredo/tasks', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (res.ok) {
        setNewTitle('');
        setNewTrack('');
        setNewRun('');
        setNewDeps('');
        setNewAcceptance('');
        setNewTopics('');
        setNewFiles('');
        setShowCreateModal(false);
        setActionMessage('Task created successfully');
        loadData();
      } else {
        const err = await res.json();
        setActionMessage(`Failed to create task: ${err.error || res.statusText}`);
      }
    } catch (err) {
      setActionMessage(`Error creating task: ${err.message}`);
    }
  };

  const handleCancelTask = async (taskId) => {
    if (!window.confirm(`Are you sure you want to cancel task ${taskId}?`)) return;
    try {
      const res = await fetch('/api/alfredo/cancel', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ task: taskId }),
      });
      if (res.ok) {
        setActionMessage(`Task ${taskId} cancelled`);
        loadData();
        if (selectedTask?.id === taskId) setSelectedTask(null);
      } else {
        const err = await res.json();
        setActionMessage(`Failed to cancel: ${err.error || res.statusText}`);
      }
    } catch (err) {
      setActionMessage(`Error cancelling task: ${err.message}`);
    }
  };

  const handleApproveTask = async (taskId) => {
    if (!window.confirm(`Approve (mark done) task ${taskId}?`)) return;
    try {
      const res = await fetch('/api/alfredo/done', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ task: taskId }),
      });
      if (res.ok) {
        setActionMessage(`Task ${taskId} approved and marked done!`);
        loadData();
        if (selectedTask?.id === taskId) {
          setSelectedTask(prev => prev ? { ...prev, status: 'DONE' } : null);
        }
      } else {
        const err = await res.json();
        setActionMessage(`Failed to approve task: ${err.error || res.statusText}`);
      }
    } catch (err) {
      setActionMessage(`Error approving task: ${err.message}`);
    }
  };

  const handleCleanupTask = async (taskId, force = false) => {
    if (!window.confirm(`Cleanup worktree/resources for task ${taskId}?`)) return;
    try {
      const res = await fetch('/api/alfredo/cleanup', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ task: taskId, force }),
      });
      if (res.ok) {
        setActionMessage(`Cleaned up task ${taskId}`);
        loadData();
      } else {
        const err = await res.json();
        setActionMessage(`Cleanup failed: ${err.error || res.statusText}`);
      }
    } catch (err) {
      setActionMessage(`Error cleaning up: ${err.message}`);
    }
  };

  const handleStartWorker = async (useWorkerFallback = false) => {
    try {
      const endpoint = useWorkerFallback ? '/api/alfredo/worker' : '/api/alfredo/sessions';
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ adapter: workerAdapter, agent: workerAgent }),
      });
      if (res.ok) {
        setActionMessage('Worker session started successfully');
        loadData();
      } else {
        const err = await res.json();
        throw new Error(err.error || res.statusText);
      }
    } catch (err) {
      // Clipboard fallback if auto-start fails or unavailable
      const fallbackText = `alfredo session start --adapter ${workerAdapter} --agent ${workerAgent}`;
      try {
        await navigator.clipboard.writeText(fallbackText);
        setActionMessage(`Worker auto-start failed (${err.message}). Command copied to clipboard: ${fallbackText}`);
      } catch (_) {
        setActionMessage(`Worker auto-start failed: ${err.message}`);
      }
    }
  };

  const handleCloseSession = async (sessionId) => {
    if (!window.confirm(`Close worker session ${sessionId}?`)) return;
    try {
      const res = await fetch('/api/alfredo/session/close', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ session: sessionId, reason: 'completed' }),
      });
      if (res.ok) {
        setActionMessage(`Session ${sessionId} closed`);
        loadData();
      } else {
        const err = await res.json();
        setActionMessage(`Failed to close session: ${err.error || res.statusText}`);
      }
    } catch (err) {
      setActionMessage(`Error closing session: ${err.message}`);
    }
  };

  const handlePackageAction = async (action, pkgId) => {
    try {
      const endpoint = action === 'install' ? '/api/alfredo/packages/install'
        : action === 'uninstall' ? '/api/alfredo/packages/uninstall'
        : '/api/alfredo/packages/update';
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ package: pkgId, target: pkgTarget, scope: pkgScope }),
      });
      if (res.ok) {
        setActionMessage(`Package ${pkgId} ${action}ed successfully`);
        loadData();
      } else {
        const err = await res.json();
        setActionMessage(`Package action failed: ${err.error || res.statusText}`);
      }
    } catch (err) {
      setActionMessage(`Error with package ${action}: ${err.message}`);
    }
  };

  const readyIds = new Set(readyTasks.map(t => t.id || t));

  const filteredTasks = tasks.filter(task => {
    if (!showCancelled && task.status === 'CANCELLED') return false;
    if (searchFilter) {
      const q = searchFilter.toLowerCase();
      const matchTitle = task.title?.toLowerCase().includes(q);
      const matchId = task.id?.toLowerCase().includes(q);
      const matchTrack = task.track?.toLowerCase().includes(q);
      if (!matchTitle && !matchId && !matchTrack) return false;
    }
    return true;
  });

  const pageTasks = filteredTasks.slice(page * pageSize, (page + 1) * pageSize);
  const totalPages = Math.max(1, Math.ceil(filteredTasks.length / pageSize));

  return React.createElement('section', { className: 'alfredo-view', 'aria-label': 'Alfredo' },
    // Header & Tabs
    React.createElement('header', { className: 'alfredo-header' },
      React.createElement('div', { className: 'alfredo-title-area' },
        React.createElement('h2', null, 'Alfredo Dashboard'),
        actionMessage && React.createElement('span', { className: 'alfredo-notice' }, actionMessage),
      ),
      React.createElement('div', { className: 'alfredo-nav-buttons' },
        React.createElement('button', {
          className: activeTab === 'kanban' ? 'active' : '',
          onClick: () => setActiveTab('kanban')
        }, '📋 Kanban'),
        React.createElement('button', {
          className: activeTab === 'workers' ? 'active' : '',
          onClick: () => setActiveTab('workers')
        }, `👥 Workers (${sessions.filter(s => s.status === 'ACTIVE').length})`),
        React.createElement('button', {
          className: activeTab === 'packages' ? 'active' : '',
          onClick: () => setActiveTab('packages')
        }, `📦 Packages (${packages.length})`),
        React.createElement('button', { className: 'alfredo-btn-primary', onClick: () => setShowCreateModal(true) }, '+ New Task'),
      ),
    ),

    // TAB 1: KANBAN
    activeTab === 'kanban' && React.createElement(React.Fragment, null,
      React.createElement('div', { className: 'alfredo-controls' },
        React.createElement('input', {
          type: 'text',
          placeholder: 'Search tasks by title, id, or track...',
          value: searchFilter,
          onChange: (e) => setSearchFilter(e.target.value),
          className: 'alfredo-search-input'
        }),
        React.createElement('label', { className: 'alfredo-checkbox-label' },
          React.createElement('input', {
            type: 'checkbox',
            checked: showCancelled,
            onChange: (e) => setShowCancelled(e.target.checked)
          }),
          ' Show Cancelled'
        ),
      ),
      React.createElement('div', { className: 'alfredo-kanban' }, COLUMNS.map(([key, label]) => {
        const columnTasks = pageTasks.filter((task) => {
          if (key === 'READY') {
            return task.status === 'READY' || readyIds.has(task.id);
          }
          if (key === 'CLAIMED') {
            return task.status === 'CLAIMED' || task.status === 'DOING';
          }
          return task.status === key;
        });

        return React.createElement('div', { className: 'alfredo-column', key },
          React.createElement('div', { className: 'alfredo-column-header' },
            React.createElement('h3', null, label),
            React.createElement('span', { className: 'alfredo-badge' }, columnTasks.length),
          ),
          React.createElement('div', { className: 'alfredo-column-scroll' },
            columnTasks.map((task) => {
              const executor = task.owner || task.previous_owner;
              const isVerifying = task.status === 'VERIFYING';
              return React.createElement('article', {
                className: `alfredo-card ${readyIds.has(task.id) ? 'alfredo-card-ready' : ''} ${isVerifying ? 'alfredo-card-verifying' : ''}`,
                key: task.id,
                onClick: () => setSelectedTask(task)
              },
                React.createElement('div', { className: 'alfredo-card-top' },
                  React.createElement('strong', null, task.title),
                  React.createElement('span', { className: `alfredo-prio ${task.priority}` }, task.priority || 'normal'),
                ),
                React.createElement('small', { className: 'alfredo-muted' }, `${task.id} · ${task.status}`),
                task.track && React.createElement('small', null, `Track: ${task.track}`),
                executor && React.createElement('div', { className: 'alfredo-card-executor' },
                  React.createElement('span', { className: 'alfredo-badge-agent', title: 'Agent' }, `🤖 ${executor.agent || 'executor'}`),
                  React.createElement('span', { className: 'alfredo-badge-model', title: 'Model / Adapter' }, `⚡ ${executor.adapter || 'adapter'}`),
                ),
                React.createElement('div', { className: 'alfredo-card-actions', onClick: (e) => e.stopPropagation() },
                  isVerifying && React.createElement('button', {
                    className: 'alfredo-btn-sm alfredo-btn-success',
                    title: 'Approve task and mark as DONE',
                    onClick: () => handleApproveTask(task.id)
                  }, '✓ Approve'),
                  task.status !== 'CANCELLED' && React.createElement('button', {
                    className: 'alfredo-btn-sm alfredo-btn-danger',
                    onClick: () => handleCancelTask(task.id)
                  }, 'Cancel'),
                  React.createElement('button', {
                    className: 'alfredo-btn-sm',
                    onClick: () => handleCleanupTask(task.id, true)
                  }, 'Cleanup'),
                )
              );
            }),
            columnTasks.length === 0 && React.createElement('div', { className: 'alfredo-empty-col' }, 'No tasks')
          )
        );
      })),
      React.createElement('nav', { className: 'alfredo-pagination', 'aria-label': 'Task pages' },
        React.createElement('button', { disabled: page === 0, onClick: () => setPage(page - 1) }, 'Previous'),
        React.createElement('span', null, `Page ${page + 1} of ${totalPages} (${filteredTasks.length} tasks)`),
        React.createElement('button', { disabled: page + 1 >= totalPages, onClick: () => setPage(page + 1) }, 'Next'),
      ),
    ),

    // TAB 2: WORKERS
    activeTab === 'workers' && React.createElement('div', { className: 'alfredo-workers-view' },
      React.createElement('div', { className: 'alfredo-section-box' },
        React.createElement('h3', null, 'Start Worker Session'),
        React.createElement('div', { className: 'alfredo-form-row' },
          React.createElement('label', null, 'Adapter:'),
          React.createElement('select', { value: workerAdapter, onChange: (e) => setWorkerAdapter(e.target.value) },
            ['codex', 'claude-code', 'cursor', 'antigravity', 'devin', 'generic', 'gemini-cli', 'via'].map(a =>
              React.createElement('option', { key: a, value: a }, a)
            )
          ),
          React.createElement('label', null, 'Agent:'),
          React.createElement('input', {
            type: 'text',
            value: workerAgent,
            onChange: (e) => setWorkerAgent(e.target.value)
          }),
          React.createElement('button', {
            className: 'alfredo-btn-primary',
            onClick: () => handleStartWorker(false)
          }, 'Start Session'),
          React.createElement('button', {
            className: 'alfredo-btn-secondary',
            onClick: () => handleStartWorker(true)
          }, 'Start via /api/alfredo/worker'),
        ),
      ),
      React.createElement('div', { className: 'alfredo-section-box' },
        React.createElement('h3', null, 'Active & Closed Sessions'),
        React.createElement('div', { className: 'alfredo-table-wrap' },
          React.createElement('table', { className: 'alfredo-table' },
            React.createElement('thead', null,
              React.createElement('tr', null,
                React.createElement('th', null, 'ID'),
                React.createElement('th', null, 'Adapter'),
                React.createElement('th', null, 'Agent'),
                React.createElement('th', null, 'Status'),
                React.createElement('th', null, 'Started At'),
                React.createElement('th', null, 'Actions'),
              )
            ),
            React.createElement('tbody', null,
              sessions.map(s =>
                React.createElement('tr', { key: s.id },
                  React.createElement('td', null, s.id),
                  React.createElement('td', null, s.adapter),
                  React.createElement('td', null, s.agent),
                  React.createElement('td', null, React.createElement('span', { className: `alfredo-status-${s.status?.toLowerCase()}` }, s.status)),
                  React.createElement('td', null, s.started_at ? new Date(s.started_at).toLocaleString() : ''),
                  React.createElement('td', null,
                    s.status === 'ACTIVE' && React.createElement('button', {
                      className: 'alfredo-btn-sm alfredo-btn-danger',
                      onClick: () => handleCloseSession(s.id)
                    }, 'Close Session')
                  )
                )
              )
            )
          )
        )
      )
    ),

    // TAB 3: PACKAGES
    activeTab === 'packages' && React.createElement('div', { className: 'alfredo-packages-view' },
      React.createElement('div', { className: 'alfredo-section-box' },
        React.createElement('h3', null, 'Package Management Catalog'),
        React.createElement('div', { className: 'alfredo-form-row' },
          React.createElement('label', null, 'Target:'),
          React.createElement('select', { value: pkgTarget, onChange: (e) => setPkgTarget(e.target.value) },
            ['dsh', 'codex', 'claude-code', 'cursor', 'antigravity', 'devin', 'generic', 'gemini-cli', 'via'].map(t =>
              React.createElement('option', { key: t, value: t }, t)
            )
          ),
          React.createElement('label', null, 'Scope:'),
          React.createElement('select', { value: pkgScope, onChange: (e) => setPkgScope(e.target.value) },
            React.createElement('option', { value: 'user' }, 'user'),
            React.createElement('option', { value: 'project' }, 'project'),
          ),
          React.createElement('button', {
            className: 'alfredo-btn-secondary',
            onClick: () => handlePackageAction('update', '')
          }, 'Update All Packages'),
        ),
      ),
      React.createElement('div', { className: 'alfredo-section-box' },
        React.createElement('h3', null, 'Available / Installed Packages'),
        React.createElement('div', { className: 'alfredo-table-wrap' },
          React.createElement('table', { className: 'alfredo-table' },
            React.createElement('thead', null,
              React.createElement('tr', null,
                React.createElement('th', null, 'Package ID'),
                React.createElement('th', null, 'Version'),
                React.createElement('th', null, 'Source'),
                React.createElement('th', null, 'Actions'),
              )
            ),
            React.createElement('tbody', null,
              packages.map(p =>
                React.createElement('tr', { key: p.id },
                  React.createElement('td', null, React.createElement('strong', null, p.id)),
                  React.createElement('td', null, p.version),
                  React.createElement('td', null, p.source),
                  React.createElement('td', { className: 'alfredo-table-actions' },
                    React.createElement('button', {
                      className: 'alfredo-btn-sm alfredo-btn-primary',
                      onClick: () => handlePackageAction('install', p.id)
                    }, 'Install'),
                    React.createElement('button', {
                      className: 'alfredo-btn-sm alfredo-btn-danger',
                      onClick: () => handlePackageAction('uninstall', p.id)
                    }, 'Uninstall'),
                  )
                )
              )
            )
          )
        )
      )
    ),

    // CREATE TASK MODAL / DRAWER
    showCreateModal && React.createElement('div', { className: 'alfredo-modal-backdrop', onClick: () => setShowCreateModal(false) },
      React.createElement('div', { className: 'alfredo-modal', onClick: (e) => e.stopPropagation() },
        React.createElement('header', { className: 'alfredo-modal-header' },
          React.createElement('h3', null, 'Create Durable Task'),
          React.createElement('button', { className: 'alfredo-close-btn', onClick: () => setShowCreateModal(false) }, '×')
        ),
        React.createElement('form', { onSubmit: handleCreateTask, className: 'alfredo-form' },
          React.createElement('label', null, 'Title *'),
          React.createElement('input', {
            type: 'text',
            required: true,
            value: newTitle,
            onChange: (e) => setNewTitle(e.target.value),
            placeholder: 'Task description / title'
          }),

          React.createElement('div', { className: 'alfredo-form-grid' },
            React.createElement('div', null,
              React.createElement('label', null, 'Priority'),
              React.createElement('select', { value: newPriority, onChange: (e) => setNewPriority(e.target.value) },
                ['low', 'normal', 'high', 'urgent'].map(p => React.createElement('option', { key: p, value: p }, p))
              )
            ),
            React.createElement('div', null,
              React.createElement('label', null, 'Track'),
              React.createElement('input', {
                type: 'text',
                value: newTrack,
                onChange: (e) => setNewTrack(e.target.value),
                placeholder: 'e.g. feature, bugfix'
              })
            ),
            React.createElement('div', null,
              React.createElement('label', null, 'Run'),
              React.createElement('input', {
                type: 'text',
                value: newRun,
                onChange: (e) => setNewRun(e.target.value),
                placeholder: 'Run script/command'
              })
            ),
          ),

          React.createElement('label', null, 'Dependencies (comma separated IDs)'),
          React.createElement('input', {
            type: 'text',
            value: newDeps,
            onChange: (e) => setNewDeps(e.target.value),
            placeholder: 'ALF-01..., ALF-02...'
          }),

          React.createElement('label', null, 'Acceptance Criteria (one per line)'),
          React.createElement('textarea', {
            rows: 3,
            value: newAcceptance,
            onChange: (e) => setNewAcceptance(e.target.value),
            placeholder: 'Criteria 1\nCriteria 2'
          }),

          React.createElement('div', { className: 'alfredo-form-grid' },
            React.createElement('div', null,
              React.createElement('label', null, 'Topics (comma separated)'),
              React.createElement('input', {
                type: 'text',
                value: newTopics,
                onChange: (e) => setNewTopics(e.target.value),
                placeholder: 'backend, ui'
              })
            ),
            React.createElement('div', null,
              React.createElement('label', null, 'Files (comma separated)'),
              React.createElement('input', {
                type: 'text',
                value: newFiles,
                onChange: (e) => setNewFiles(e.target.value),
                placeholder: 'src/index.js'
              })
            ),
          ),

          React.createElement('div', { className: 'alfredo-modal-footer' },
            React.createElement('button', { type: 'button', onClick: () => setShowCreateModal(false) }, 'Cancel'),
            React.createElement('button', { type: 'submit', className: 'alfredo-btn-primary' }, 'Create Task'),
          )
        )
      )
    ),

    // TASK DETAILS PANEL / DRAWER
    selectedTask && React.createElement('div', { className: 'alfredo-modal-backdrop', onClick: () => setSelectedTask(null) },
      React.createElement('div', { className: 'alfredo-drawer', onClick: (e) => e.stopPropagation() },
        React.createElement('header', { className: 'alfredo-modal-header' },
          React.createElement('div', null,
            React.createElement('span', { className: `alfredo-prio ${selectedTask.priority}` }, selectedTask.priority),
            React.createElement('h3', null, selectedTask.title),
          ),
          React.createElement('button', { className: 'alfredo-close-btn', onClick: () => setSelectedTask(null) }, '×')
        ),
        React.createElement('div', { className: 'alfredo-drawer-body' },
          React.createElement('div', { className: 'alfredo-meta-grid' },
            React.createElement('div', null, React.createElement('strong', null, 'ID: '), selectedTask.id),
            React.createElement('div', null, React.createElement('strong', null, 'Status: '), selectedTask.status),
            React.createElement('div', null, React.createElement('strong', null, 'Track: '), selectedTask.track || 'none'),
            React.createElement('div', null, React.createElement('strong', null, 'Run: '), selectedTask.run || 'none'),
            React.createElement('div', null, React.createElement('strong', null, 'Created: '), selectedTask.created_at ? new Date(selectedTask.created_at).toLocaleString() : 'N/A'),
            React.createElement('div', null, React.createElement('strong', null, 'Updated: '), selectedTask.updated_at ? new Date(selectedTask.updated_at).toLocaleString() : 'N/A'),
          ),

          (selectedTask.owner || selectedTask.previous_owner) && React.createElement('div', { className: 'alfredo-section-block' },
            React.createElement('h4', null, 'Executed By (Agent & Model / Adapter)'),
            React.createElement('div', { className: 'alfredo-executor-details' },
              React.createElement('span', { className: 'alfredo-badge-agent' }, `🤖 Agent: ${(selectedTask.owner || selectedTask.previous_owner).agent || 'executor'}`),
              React.createElement('span', { className: 'alfredo-badge-model' }, `⚡ Model / Adapter: ${(selectedTask.owner || selectedTask.previous_owner).adapter || 'codex'}`),
              (selectedTask.owner || selectedTask.previous_owner).session && React.createElement('span', { className: 'alfredo-badge-session' }, `Session: ${(selectedTask.owner || selectedTask.previous_owner).session}`),
            )
          ),

          selectedTask.dependencies && selectedTask.dependencies.length > 0 && React.createElement('div', { className: 'alfredo-section-block' },
            React.createElement('h4', null, 'Dependencies'),
            React.createElement('ul', null, selectedTask.dependencies.map(d => React.createElement('li', { key: d }, d)))
          ),

          selectedTask.acceptance && selectedTask.acceptance.length > 0 && React.createElement('div', { className: 'alfredo-section-block' },
            React.createElement('h4', null, 'Acceptance Criteria'),
            React.createElement('ul', null, selectedTask.acceptance.map((a, i) => React.createElement('li', { key: i }, a)))
          ),

          selectedTask.checkpoint && React.createElement('div', { className: 'alfredo-section-block' },
            React.createElement('h4', null, 'Checkpoint State'),
            selectedTask.checkpoint.current && React.createElement('p', null, React.createElement('strong', null, 'Current: '), selectedTask.checkpoint.current),
            selectedTask.checkpoint.completed && selectedTask.checkpoint.completed.length > 0 && React.createElement(React.Fragment, null,
              React.createElement('strong', null, 'Completed Steps:'),
              React.createElement('ul', null, selectedTask.checkpoint.completed.map((c, i) => React.createElement('li', { key: i }, c)))
            ),
            selectedTask.checkpoint.changed_files && selectedTask.checkpoint.changed_files.length > 0 && React.createElement(React.Fragment, null,
              React.createElement('strong', null, 'Changed Files:'),
              React.createElement('ul', null, selectedTask.checkpoint.changed_files.map((f, i) => React.createElement('li', { key: i }, f)))
            ),
          ),

          // TASK EVENTS TIMELINE
          React.createElement('div', { className: 'alfredo-section-block' },
            React.createElement('h4', null, 'Task Events Timeline'),
            taskEvents.length === 0 && React.createElement('p', { className: 'alfredo-muted' }, 'No recorded events for this task.'),
            React.createElement('div', { className: 'alfredo-timeline' },
              taskEvents.map(ev =>
                React.createElement('div', { className: 'alfredo-timeline-item', key: ev.id },
                  React.createElement('div', { className: 'alfredo-timeline-badge' }, ev.type),
                  React.createElement('div', { className: 'alfredo-timeline-content' },
                    React.createElement('small', { className: 'alfredo-muted' }, new Date(ev.created_at).toLocaleString()),
                    React.createElement('pre', null, JSON.stringify(ev.data || {}, null, 2))
                  )
                )
              )
            )
          ),

          React.createElement('div', { className: 'alfredo-drawer-footer' },
            selectedTask.status === 'VERIFYING' && React.createElement('button', {
              className: 'alfredo-btn-success',
              onClick: () => handleApproveTask(selectedTask.id)
            }, '✓ Approve Task (Mark Done)'),
            React.createElement('button', {
              className: 'alfredo-btn-danger',
              onClick: () => handleCancelTask(selectedTask.id)
            }, 'Cancel Task'),
            React.createElement('button', {
              className: 'alfredo-btn-secondary',
              onClick: () => handleCleanupTask(selectedTask.id, true)
            }, 'Cleanup Worktree'),
          )
        )
      )
    )
  );
}

function apply(ctx) {
  ctx.slots.inject('conversation.view', () => ctx.slots.register({
    name: 'conversation.view',
    id: 'alfredo',
    order: 20,
    label: () => 'Alfredo',
    inject: () => ({})
  }, AlfredoView));
}



const CSS = ".alfredo-view {\n  height: 100%;\n  overflow: auto;\n  padding: 1.25rem;\n  color: var(--foreground, #e2e8f0);\n  background: var(--background, #0f172a);\n  font-family: inherit;\n  box-sizing: border-box;\n}\n\n.alfredo-header {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: 1rem;\n  margin-bottom: 1rem;\n  flex-wrap: wrap;\n}\n\n.alfredo-title-area {\n  display: flex;\n  align-items: center;\n  gap: 1rem;\n}\n\n.alfredo-title-area h2 {\n  margin: 0;\n  font-size: 1.5rem;\n  font-weight: 700;\n}\n\n.alfredo-notice {\n  font-size: 0.85rem;\n  padding: 0.25rem 0.5rem;\n  background: rgba(59, 130, 246, 0.2);\n  border: 1px solid rgba(59, 130, 246, 0.4);\n  border-radius: 4px;\n  color: #93c5fd;\n}\n\n.alfredo-nav-buttons {\n  display: flex;\n  gap: 0.5rem;\n  align-items: center;\n}\n\n.alfredo-nav-buttons button {\n  background: transparent;\n  border: 1px solid var(--border, #334155);\n  color: var(--foreground, #e2e8f0);\n  padding: 0.5rem 0.85rem;\n  border-radius: 0.375rem;\n  cursor: pointer;\n  font-weight: 500;\n  transition: all 0.2s;\n}\n\n.alfredo-nav-buttons button:hover {\n  background: rgba(255, 255, 255, 0.05);\n}\n\n.alfredo-nav-buttons button.active {\n  background: #2563eb;\n  border-color: #2563eb;\n  color: #fff;\n}\n\n.alfredo-btn-primary {\n  background: #2563eb !important;\n  color: #fff !important;\n  border-color: #2563eb !important;\n}\n\n.alfredo-btn-primary:hover {\n  background: #1d4ed8 !important;\n}\n\n.alfredo-btn-secondary {\n  background: #475569 !important;\n  color: #fff !important;\n  border-color: #475569 !important;\n}\n\n.alfredo-btn-danger {\n  background: #dc2626 !important;\n  color: #fff !important;\n  border-color: #dc2626 !important;\n}\n\n.alfredo-btn-success {\n  background: #059669 !important;\n  color: #fff !important;\n  border-color: #059669 !important;\n  font-weight: 600 !important;\n}\n\n.alfredo-btn-success:hover {\n  background: #047857 !important;\n}\n\n.alfredo-controls {\n  display: flex;\n  gap: 1rem;\n  align-items: center;\n  margin-bottom: 1rem;\n}\n\n.alfredo-search-input {\n  flex: 1;\n  max-width: 320px;\n  padding: 0.5rem 0.75rem;\n  background: var(--card, #1e293b);\n  border: 1px solid var(--border, #334155);\n  border-radius: 0.375rem;\n  color: var(--foreground, #e2e8f0);\n}\n\n.alfredo-checkbox-label {\n  display: flex;\n  align-items: center;\n  gap: 0.5rem;\n  font-size: 0.9rem;\n  cursor: pointer;\n}\n\n.alfredo-kanban {\n  display: grid;\n  grid-template-columns: repeat(6, minmax(16rem, 1fr));\n  gap: 1rem;\n  min-width: 102rem;\n  overflow-x: auto;\n  padding-bottom: 1rem;\n}\n\n.alfredo-column {\n  border: 1px solid var(--border, #334155);\n  border-radius: 0.5rem;\n  background: rgba(30, 41, 59, 0.4);\n  display: flex;\n  flex-direction: column;\n  max-height: calc(100vh - 240px);\n}\n\n.alfredo-column-header {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  padding: 0.75rem 1rem;\n  border-bottom: 1px solid var(--border, #334155);\n  background: rgba(15, 23, 42, 0.5);\n  border-top-left-radius: 0.5rem;\n  border-top-right-radius: 0.5rem;\n}\n\n.alfredo-column-header h3 {\n  margin: 0;\n  font-size: 0.95rem;\n  font-weight: 600;\n}\n\n.alfredo-badge {\n  background: var(--border, #334155);\n  padding: 0.1rem 0.4rem;\n  border-radius: 9999px;\n  font-size: 0.75rem;\n  font-weight: 600;\n}\n\n.alfredo-column-scroll {\n  overflow-y: auto;\n  padding: 0.5rem;\n  flex: 1;\n  display: flex;\n  flex-direction: column;\n  gap: 0.5rem;\n  scroll-behavior: smooth;\n}\n\n.alfredo-card {\n  display: flex;\n  flex-direction: column;\n  gap: 0.35rem;\n  padding: 0.75rem;\n  border: 1px solid var(--border, #334155);\n  border-radius: 0.375rem;\n  background: var(--card, #1e293b);\n  cursor: pointer;\n  transition: transform 0.1s, border-color 0.2s;\n}\n\n.alfredo-card:hover {\n  border-color: #3b82f6;\n  transform: translateY(-1px);\n}\n\n.alfredo-card-ready {\n  border-left: 3px solid #10b981;\n}\n\n.alfredo-card-verifying {\n  border-left: 3px solid #f59e0b;\n  background: rgba(245, 158, 11, 0.05);\n}\n\n.alfredo-card-executor {\n  display: flex;\n  gap: 0.35rem;\n  flex-wrap: wrap;\n  margin: 0.25rem 0;\n}\n\n.alfredo-badge-agent {\n  background: rgba(59, 130, 246, 0.18);\n  border: 1px solid rgba(59, 130, 246, 0.4);\n  color: #93c5fd;\n  font-size: 0.72rem;\n  padding: 0.1rem 0.35rem;\n  border-radius: 4px;\n  font-weight: 500;\n}\n\n.alfredo-badge-model {\n  background: rgba(168, 85, 247, 0.18);\n  border: 1px solid rgba(168, 85, 247, 0.4);\n  color: #d8b4fe;\n  font-size: 0.72rem;\n  padding: 0.1rem 0.35rem;\n  border-radius: 4px;\n  font-weight: 500;\n}\n\n.alfredo-badge-session {\n  background: rgba(148, 163, 184, 0.18);\n  border: 1px solid rgba(148, 163, 184, 0.4);\n  color: #cbd5e1;\n  font-size: 0.72rem;\n  padding: 0.1rem 0.35rem;\n  border-radius: 4px;\n  font-weight: 500;\n}\n\n.alfredo-executor-details {\n  display: flex;\n  gap: 0.5rem;\n  flex-wrap: wrap;\n  align-items: center;\n  margin-top: 0.25rem;\n}\n\n.alfredo-card-top {\n  display: flex;\n  justify-content: space-between;\n  align-items: flex-start;\n  gap: 0.5rem;\n}\n\n.alfredo-card-top strong {\n  font-size: 0.9rem;\n  line-height: 1.25;\n}\n\n.alfredo-prio {\n  font-size: 0.7rem;\n  text-transform: uppercase;\n  padding: 0.1rem 0.35rem;\n  border-radius: 3px;\n  font-weight: 700;\n}\n\n.alfredo-prio.normal { background: #334155; color: #cbd5e1; }\n.alfredo-prio.high { background: #d97706; color: #fff; }\n.alfredo-prio.urgent { background: #dc2626; color: #fff; }\n.alfredo-prio.low { background: #475569; color: #94a3b8; }\n\n.alfredo-muted {\n  color: #94a3b8;\n  font-size: 0.8rem;\n}\n\n.alfredo-card-actions {\n  display: flex;\n  gap: 0.5rem;\n  margin-top: 0.25rem;\n}\n\n.alfredo-btn-sm {\n  padding: 0.2rem 0.5rem;\n  font-size: 0.75rem;\n  border-radius: 0.25rem;\n  border: 1px solid var(--border, #334155);\n  background: transparent;\n  color: var(--foreground, #e2e8f0);\n  cursor: pointer;\n}\n\n.alfredo-btn-sm:hover {\n  background: rgba(255, 255, 255, 0.1);\n}\n\n.alfredo-empty-col {\n  text-align: center;\n  color: #64748b;\n  font-size: 0.85rem;\n  padding: 1.5rem;\n}\n\n.alfredo-pagination {\n  position: sticky;\n  bottom: 0;\n  padding: 0.75rem 0;\n  background: var(--background, #0f172a);\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  border-top: 1px solid var(--border, #334155);\n  margin-top: 1rem;\n}\n\n.alfredo-section-box {\n  background: rgba(30, 41, 59, 0.5);\n  border: 1px solid var(--border, #334155);\n  border-radius: 0.5rem;\n  padding: 1.25rem;\n  margin-bottom: 1.5rem;\n}\n\n.alfredo-section-box h3 {\n  margin-top: 0;\n  margin-bottom: 1rem;\n  font-size: 1.1rem;\n}\n\n.alfredo-form-row {\n  display: flex;\n  gap: 0.75rem;\n  align-items: center;\n  flex-wrap: wrap;\n}\n\n.alfredo-form-row input, .alfredo-form-row select {\n  padding: 0.4rem 0.6rem;\n  background: var(--card, #1e293b);\n  border: 1px solid var(--border, #334155);\n  border-radius: 0.375rem;\n  color: var(--foreground, #e2e8f0);\n}\n\n.alfredo-table-wrap {\n  overflow-x: auto;\n}\n\n.alfredo-table {\n  width: 100%;\n  border-collapse: collapse;\n  text-align: left;\n  font-size: 0.9rem;\n}\n\n.alfredo-table th, .alfredo-table td {\n  padding: 0.75rem;\n  border-bottom: 1px solid var(--border, #334155);\n}\n\n.alfredo-table th {\n  background: rgba(15, 23, 42, 0.6);\n  font-weight: 600;\n}\n\n.alfredo-table-actions {\n  display: flex;\n  gap: 0.5rem;\n}\n\n.alfredo-status-active { color: #10b981; font-weight: 600; }\n.alfredo-status-closed { color: #64748b; font-weight: 600; }\n\n.alfredo-modal-backdrop {\n  position: fixed;\n  inset: 0;\n  background: rgba(0, 0, 0, 0.7);\n  display: flex;\n  align-items: center;\n  justify-content: center;\n  z-index: 1000;\n  padding: 1rem;\n}\n\n.alfredo-modal {\n  background: var(--background, #0f172a);\n  border: 1px solid var(--border, #334155);\n  border-radius: 0.5rem;\n  width: 100%;\n  max-width: 600px;\n  max-height: 90vh;\n  overflow-y: auto;\n  padding: 1.5rem;\n}\n\n.alfredo-drawer {\n  position: fixed;\n  top: 0;\n  right: 0;\n  bottom: 0;\n  width: 100%;\n  max-width: 650px;\n  background: var(--background, #0f172a);\n  border-left: 1px solid var(--border, #334155);\n  box-shadow: -4px 0 25px rgba(0,0,0,0.5);\n  z-index: 1001;\n  display: flex;\n  flex-direction: column;\n  overflow: hidden;\n}\n\n.alfredo-modal-header {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  padding-bottom: 1rem;\n  border-bottom: 1px solid var(--border, #334155);\n  margin-bottom: 1rem;\n}\n\n.alfredo-modal-header h3 {\n  margin: 0;\n}\n\n.alfredo-close-btn {\n  background: transparent;\n  border: none;\n  font-size: 1.5rem;\n  color: var(--foreground, #e2e8f0);\n  cursor: pointer;\n}\n\n.alfredo-form {\n  display: flex;\n  flex-direction: column;\n  gap: 0.75rem;\n}\n\n.alfredo-form label {\n  font-size: 0.85rem;\n  font-weight: 500;\n  color: #cbd5e1;\n}\n\n.alfredo-form input, .alfredo-form select, .alfredo-form textarea {\n  padding: 0.5rem;\n  background: var(--card, #1e293b);\n  border: 1px solid var(--border, #334155);\n  border-radius: 0.375rem;\n  color: var(--foreground, #e2e8f0);\n  font-family: inherit;\n}\n\n.alfredo-form-grid {\n  display: grid;\n  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));\n  gap: 0.75rem;\n}\n\n.alfredo-modal-footer {\n  display: flex;\n  justify-content: flex-end;\n  gap: 0.75rem;\n  margin-top: 1rem;\n  padding-top: 1rem;\n  border-top: 1px solid var(--border, #334155);\n}\n\n.alfredo-drawer-body {\n  flex: 1;\n  overflow-y: auto;\n  padding: 0 1.5rem 1.5rem 1.5rem;\n  display: flex;\n  flex-direction: column;\n  gap: 1rem;\n}\n\n.alfredo-meta-grid {\n  display: grid;\n  grid-template-columns: repeat(2, 1fr);\n  gap: 0.5rem;\n  font-size: 0.9rem;\n  background: rgba(30, 41, 59, 0.4);\n  padding: 0.75rem;\n  border-radius: 0.375rem;\n  border: 1px solid var(--border, #334155);\n}\n\n.alfredo-section-block {\n  border-top: 1px solid var(--border, #334155);\n  padding-top: 0.75rem;\n}\n\n.alfredo-section-block h4 {\n  margin: 0 0 0.5rem 0;\n  font-size: 0.95rem;\n  color: #93c5fd;\n}\n\n.alfredo-section-block ul {\n  margin: 0;\n  padding-left: 1.25rem;\n  font-size: 0.85rem;\n}\n\n.alfredo-timeline {\n  display: flex;\n  flex-direction: column;\n  gap: 0.75rem;\n  max-height: 250px;\n  overflow-y: auto;\n}\n\n.alfredo-timeline-item {\n  display: flex;\n  gap: 0.75rem;\n  align-items: flex-start;\n  background: var(--card, #1e293b);\n  padding: 0.5rem 0.75rem;\n  border-radius: 0.375rem;\n  border: 1px solid var(--border, #334155);\n}\n\n.alfredo-timeline-badge {\n  background: #2563eb;\n  color: #fff;\n  font-size: 0.7rem;\n  padding: 0.15rem 0.4rem;\n  border-radius: 3px;\n  text-transform: uppercase;\n  font-weight: 700;\n  white-space: nowrap;\n}\n\n.alfredo-timeline-content {\n  flex: 1;\n  display: flex;\n  flex-direction: column;\n  gap: 0.25rem;\n}\n\n.alfredo-timeline-content pre {\n  margin: 0;\n  font-size: 0.75rem;\n  background: rgba(15, 23, 42, 0.6);\n  padding: 0.35rem;\n  border-radius: 3px;\n  overflow-x: auto;\n}\n\n.alfredo-drawer-footer {\n  padding: 1rem 1.5rem;\n  border-top: 1px solid var(--border, #334155);\n  display: flex;\n  justify-content: flex-end;\n  gap: 0.75rem;\n  background: var(--background, #0f172a);\n}\n";
const applyWithStyle = (ctx) => {
  const style = document.createElement('style');
  style.setAttribute('data-alfredo', '');
  style.textContent = CSS;
  document.head.appendChild(style);
  ctx.effect(() => () => style.remove());
  return apply(ctx);
};
exports.apply = applyWithStyle;
exports.inject = ['slots'];
return module.exports;
} });
