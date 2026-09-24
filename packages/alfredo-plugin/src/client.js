import React from 'react';
import { createRoot } from 'react-dom/client';

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

export function apply(ctx) {
  ctx.slots.inject('conversation.view', () => ctx.slots.register({
    name: 'conversation.view',
    id: 'alfredo',
    order: 20,
    label: () => 'Alfredo',
    inject: () => ({})
  }, AlfredoView));
}

export default { apply };
