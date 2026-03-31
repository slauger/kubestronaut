// Quiz State
let allQuestions = [];
let currentQuestions = [];
let currentQuestionIndex = 0;
let questionsAnswered = 0;
let correctCount = 0;
let wrongCount = 0;
let wrongQuestionIds = [];
let seenQuestionIds = [];
let currentCatalog = '';

// Exam Mode State
let examMode = false;
let timerInterval = null;
let timeRemaining = 0;

// Catalog configuration
const CATALOGS = {
    'kcna': { name: 'KCNA - Kubernetes and Cloud Native Associate', passingScore: 75, examDuration: 90, totalQuestions: 60 },
    'kcsa': { name: 'KCSA - Kubernetes and Cloud Native Security Associate', passingScore: 75, examDuration: 90, totalQuestions: 60 },
    'cka':  { name: 'CKA - Certified Kubernetes Administrator', passingScore: 66, examDuration: 120, totalQuestions: 17 },
    'ckad': { name: 'CKAD - Certified Kubernetes Application Developer', passingScore: 66, examDuration: 120, totalQuestions: 17 },
    'cks':  { name: 'CKS - Certified Kubernetes Security Specialist', passingScore: 67, examDuration: 120, totalQuestions: 17 },
};

// Load questions from JSON
async function loadQuestions() {
    try {
        const catalogSelect = document.getElementById('catalogFilter');
        const catalogFile = catalogSelect ? catalogSelect.value : 'questions-kcna.json';

        currentCatalog = catalogFile.replace('.json', '').replace('questions-', '');

        const response = await fetch(catalogFile);
        allQuestions = await response.json();
        loadWrongQuestions();
        loadSeenQuestions();
        console.log(`Loaded ${allQuestions.length} questions from ${catalogFile} (catalog: ${currentCatalog})`);

        const questionCountInput = document.getElementById('questionCount');
        questionCountInput.max = allQuestions.length;

        updateProgressDisplay();
    } catch (error) {
        console.error('Error loading questions:', error);
        alert('Error loading questions. Please reload the page.');
    }
}

// Start Quiz
function startQuiz() {
    const count = parseInt(document.getElementById('questionCount').value);
    const randomize = document.getElementById('randomize').checked;

    let filteredQuestions = [...allQuestions];

    if (randomize) {
        filteredQuestions = shuffleArray(filteredQuestions);
    }

    currentQuestions = filteredQuestions.slice(0, Math.min(count, filteredQuestions.length));

    if (currentQuestions.length === 0) {
        alert('No questions found!');
        return;
    }

    currentQuestionIndex = 0;
    questionsAnswered = 0;
    correctCount = 0;
    wrongCount = 0;

    // Check exam mode
    examMode = document.getElementById('examMode')?.checked ?? false;
    if (examMode) {
        startTimer(currentQuestions.length);
    }

    document.getElementById('controls').classList.add('hidden');
    document.getElementById('quizCard').classList.remove('hidden');
    document.getElementById('progress').classList.remove('hidden');
    document.getElementById('results').classList.add('hidden');

    displayQuestion();
}

// Start exam timer
function startTimer(questionCount) {
    const config = CATALOGS[currentCatalog];
    if (!config) return;

    // Scale time proportionally to question count
    const totalMinutes = (questionCount / config.totalQuestions) * config.examDuration;
    timeRemaining = Math.ceil(totalMinutes * 60);

    const timerEl = document.getElementById('timer');
    if (timerEl) {
        timerEl.classList.remove('hidden');
    }

    updateTimerDisplay();

    timerInterval = setInterval(() => {
        timeRemaining--;
        updateTimerDisplay();

        if (timeRemaining <= 0) {
            clearInterval(timerInterval);
            timerInterval = null;
            showResults();
        }
    }, 1000);
}

// Update timer display
function updateTimerDisplay() {
    const timerEl = document.getElementById('timerText');
    if (!timerEl) return;

    const minutes = Math.floor(timeRemaining / 60);
    const seconds = timeRemaining % 60;
    timerEl.textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;

    // Warning colors
    if (timeRemaining <= 60) {
        timerEl.style.color = '#f44336';
        timerEl.style.fontWeight = '700';
    } else if (timeRemaining <= 300) {
        timerEl.style.color = '#ff9800';
        timerEl.style.fontWeight = '600';
    } else {
        timerEl.style.color = '#666';
        timerEl.style.fontWeight = '600';
    }
}

// Stop timer
function stopTimer() {
    if (timerInterval) {
        clearInterval(timerInterval);
        timerInterval = null;
    }
    const timerEl = document.getElementById('timer');
    if (timerEl) timerEl.classList.add('hidden');
}

// Display current question
function displayQuestion() {
    const question = currentQuestions[currentQuestionIndex];

    const randomizeAnswers = document.getElementById('randomizeAnswers')?.checked ?? false;
    if (randomizeAnswers && !question._answersShuffled) {
        shuffleAnswers(question);
        question._answersShuffled = true;
    }

    document.getElementById('questionNumber').textContent =
        `Question ${currentQuestionIndex + 1} of ${currentQuestions.length}`;
    document.getElementById('category').textContent = question.category;

    let questionHTML = `<p style="margin-bottom: 20px;">${question.question}</p>`;

    // Add images if present
    if (question.images && question.images.length > 0) {
        questionHTML += '<div style="margin: 20px 0;">';
        question.images.forEach(img => {
            questionHTML += `<img src="data:${img.mime_type};base64,${img.data}" style="max-width: 100%; border-radius: 8px; margin: 10px 0;" alt="Question image">`;
        });
        questionHTML += '</div>';
    }

    // Add answer options
    if (question.multiple_choice) {
        questionHTML += '<div style="margin-top: 20px;" id="answerOptions">';
        question.answers.forEach((answer, idx) => {
            const letter = String.fromCharCode(97 + idx).toUpperCase();
            questionHTML += `
                <div class="answer-option" data-index="${idx}" style="padding: 15px; margin: 8px 0; background: #f8f9fa; border-radius: 8px; cursor: pointer; border: 2px solid transparent; transition: all 0.2s;">
                    <label style="cursor: pointer; display: flex; align-items: center; width: 100%;">
                        <input type="checkbox" id="answer_${idx}" style="margin-right: 10px; width: 18px; height: 18px; cursor: pointer;">
                        <strong style="margin-right: 8px;">${letter})</strong> ${answer}
                    </label>
                </div>`;
        });
        questionHTML += '</div>';
        questionHTML += '<button class="btn-primary" onclick="checkAnswer()" style="margin-top: 20px; width: 100%;">Submit Answer</button>';
    } else {
        questionHTML += '<div style="margin-top: 20px;" id="answerOptions">';
        question.answers.forEach((answer, idx) => {
            const letter = String.fromCharCode(97 + idx).toUpperCase();
            questionHTML += `
                <div class="answer-option" onclick="selectAnswer(${idx})" data-index="${idx}" style="padding: 15px; margin: 8px 0; background: #f8f9fa; border-radius: 8px; cursor: pointer; border: 2px solid transparent; transition: all 0.2s;">
                    <strong>${letter})</strong> ${answer}
                </div>`;
        });
        questionHTML += '</div>';
    }

    document.getElementById('question').innerHTML = questionHTML;
    document.getElementById('answerReveal').classList.add('hidden');
    document.getElementById('feedbackSection').classList.add('hidden');
    updateProgress();
}

// Select answer for single choice
function selectAnswer(selectedIndex) {
    const question = currentQuestions[currentQuestionIndex];
    const answerOptions = document.querySelectorAll('.answer-option');

    if (answerOptions[0].style.pointerEvents === 'none') return;

    const isCorrect = question.correct === selectedIndex;

    answerOptions.forEach(opt => opt.style.pointerEvents = 'none');

    answerOptions.forEach((opt) => {
        const dataIdx = parseInt(opt.getAttribute('data-index'));
        if (dataIdx === question.correct) {
            opt.style.background = '#4caf50';
            opt.style.color = 'white';
            opt.style.borderColor = '#45a049';
        } else if (dataIdx === selectedIndex && !isCorrect) {
            opt.style.background = '#f44336';
            opt.style.color = 'white';
            opt.style.borderColor = '#da190b';
        }
    });

    showFeedback(isCorrect);
}

// Check answer for multiple choice
function checkAnswer() {
    const question = currentQuestions[currentQuestionIndex];
    const answerOptions = document.querySelectorAll('.answer-option');

    const selected = [];
    answerOptions.forEach((opt) => {
        const checkbox = opt.querySelector('input[type="checkbox"]');
        if (checkbox && checkbox.checked) {
            selected.push(parseInt(opt.getAttribute('data-index')));
        }
    });

    if (selected.length === 0) {
        alert('Please select at least one answer!');
        return;
    }

    const correctSet = new Set(Array.isArray(question.correct) ? question.correct : [question.correct]);
    const selectedSet = new Set(selected);
    const isCorrect = correctSet.size === selectedSet.size &&
                      [...correctSet].every(x => selectedSet.has(x));

    answerOptions.forEach(opt => {
        opt.style.pointerEvents = 'none';
        const checkbox = opt.querySelector('input[type="checkbox"]');
        if (checkbox) checkbox.disabled = true;
    });

    answerOptions.forEach((opt) => {
        const dataIdx = parseInt(opt.getAttribute('data-index'));
        const correctIndices = Array.isArray(question.correct) ? question.correct : [question.correct];

        if (correctIndices.includes(dataIdx)) {
            opt.style.background = '#4caf50';
            opt.style.color = 'white';
            opt.style.borderColor = '#45a049';
        } else if (selected.includes(dataIdx)) {
            opt.style.background = '#f44336';
            opt.style.color = 'white';
            opt.style.borderColor = '#da190b';
        }
    });

    const submitBtn = document.querySelector('#question button');
    if (submitBtn) submitBtn.style.display = 'none';

    showFeedback(isCorrect);
}

// Show feedback section
function showFeedback(isCorrect) {
    const question = currentQuestions[currentQuestionIndex];
    const feedbackSection = document.getElementById('feedbackSection');

    let feedbackHTML = '';

    if (isCorrect) {
        feedbackHTML += '<div style="background: #d4edda; border: 2px solid #4caf50; padding: 15px; border-radius: 8px; margin: 20px 0;">';
        feedbackHTML += '<strong style="color: #155724;">Correct!</strong>';
    } else {
        feedbackHTML += '<div style="background: #f8d7da; border: 2px solid #f44336; padding: 15px; border-radius: 8px; margin: 20px 0;">';
        feedbackHTML += '<strong style="color: #721c24;">Incorrect!</strong>';
    }

    feedbackHTML += `<div style="margin-top: 10px; color: #333;">${question.explanation}</div>`;

    if (question.reference) {
        feedbackHTML += `<div style="margin-top: 10px;"><a href="${question.reference}" target="_blank" style="color: #3f51b5; font-weight: 600;">Read more in the Kubernetes docs &rarr;</a></div>`;
    }

    feedbackHTML += '</div>';
    feedbackHTML += `<button class="btn-primary" onclick="continueToNext(${isCorrect})" style="width: 100%; margin-top: 10px;">Next &rarr;</button>`;

    feedbackSection.innerHTML = feedbackHTML;
    feedbackSection.classList.remove('hidden');
}

// Continue to next question
function continueToNext(wasCorrect) {
    if (wasCorrect) {
        markCorrect();
    } else {
        markWrong();
    }
}

// Mark question as correct
function markCorrect() {
    correctCount++;
    const question = currentQuestions[currentQuestionIndex];

    if (!seenQuestionIds.includes(question.id)) {
        seenQuestionIds.push(question.id);
        saveSeenQuestions();
    }

    nextQuestion();
}

// Mark question as wrong
function markWrong() {
    wrongCount++;
    const question = currentQuestions[currentQuestionIndex];

    if (!wrongQuestionIds.includes(question.id)) {
        wrongQuestionIds.push(question.id);
        saveWrongQuestions();
    }

    if (!seenQuestionIds.includes(question.id)) {
        seenQuestionIds.push(question.id);
        saveSeenQuestions();
    }

    nextQuestion();
}

// Go to next question
function nextQuestion() {
    currentQuestionIndex++;
    questionsAnswered++;

    if (currentQuestionIndex >= currentQuestions.length) {
        showResults();
    } else {
        displayQuestion();
    }
}

// Update progress bar
function updateProgress() {
    const progress = (questionsAnswered / currentQuestions.length) * 100;
    document.getElementById('progressBar').style.width = `${progress}%`;
    document.getElementById('progressText').textContent =
        `${questionsAnswered}/${currentQuestions.length}`;
}

// Show results
function showResults() {
    stopTimer();

    document.getElementById('quizCard').classList.add('hidden');
    document.getElementById('progress').classList.add('hidden');
    document.getElementById('results').classList.remove('hidden');

    const percentage = questionsAnswered > 0 ? Math.round((correctCount / questionsAnswered) * 100) : 0;
    const config = CATALOGS[currentCatalog];
    const passingScore = config ? config.passingScore : 66;
    const passed = percentage >= passingScore;

    const resultsDiv = document.getElementById('results');
    let html = `<h2>Quiz Complete!</h2>`;

    // Pass/Fail indicator
    if (examMode) {
        if (passed) {
            html += `<div style="background: #d4edda; border: 2px solid #4caf50; padding: 20px; border-radius: 10px; margin: 20px 0;">
                <div style="font-size: 28px; font-weight: 700; color: #155724;">PASS</div>
                <div style="color: #155724; margin-top: 5px;">Passing score: ${passingScore}%</div>
            </div>`;
        } else {
            html += `<div style="background: #f8d7da; border: 2px solid #f44336; padding: 20px; border-radius: 10px; margin: 20px 0;">
                <div style="font-size: 28px; font-weight: 700; color: #721c24;">FAIL</div>
                <div style="color: #721c24; margin-top: 5px;">Passing score: ${passingScore}% &mdash; You scored ${percentage}%</div>
            </div>`;
        }
    }

    html += `<div class="score">${correctCount}/${questionsAnswered} correct</div>`;
    html += `<p style="font-size: 24px; color: #3f51b5; margin: 20px 0;">${percentage}%</p>`;

    html += `<div style="text-align: left; background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 20px 0;">
        <div style="margin-bottom: 10px;">Correct: <strong>${correctCount}</strong></div>
        <div style="margin-bottom: 10px;">Incorrect: <strong>${wrongCount}</strong></div>
        <div>Unanswered: <strong>${currentQuestions.length - questionsAnswered}</strong></div>
    </div>`;

    if (wrongQuestionIds.length > 0) {
        html += `<div style="background: #fff3cd; padding: 15px; border-radius: 10px; margin: 20px 0;">
            <strong>Tip:</strong> You answered ${wrongQuestionIds.length} question(s) incorrectly.
            <br>They are automatically saved for later review!
        </div>`;
    }

    html += `<button class="btn-primary" onclick="resetQuiz()">Start New Quiz</button>`;

    if (wrongQuestionIds.length > 0) {
        html += `<button class="btn-wrong" onclick="reviewWrongQuestions()" style="margin-top: 10px;">
            Review Incorrect Questions (${wrongQuestionIds.length})
        </button>`;
    }

    resultsDiv.innerHTML = html;
}

// Review only wrong questions
function reviewWrongQuestions() {
    startQuizWrongOnly();
}

// Reset quiz
function resetQuiz() {
    stopTimer();
    document.getElementById('controls').classList.remove('hidden');
    document.getElementById('results').classList.add('hidden');
    updateProgressDisplay();
}

// Start quiz with only unseen questions
function startQuizNewOnly() {
    const unseenQuestions = allQuestions.filter(q => !seenQuestionIds.includes(q.id));

    if (unseenQuestions.length === 0) {
        alert('You have already answered all questions!\n\nUse "Reset Progress" to start over.');
        return;
    }

    currentQuestions = shuffleArray(unseenQuestions);
    currentQuestionIndex = 0;
    questionsAnswered = 0;
    correctCount = 0;
    wrongCount = 0;

    examMode = document.getElementById('examMode')?.checked ?? false;
    if (examMode) {
        startTimer(currentQuestions.length);
    }

    document.getElementById('controls').classList.add('hidden');
    document.getElementById('quizCard').classList.remove('hidden');
    document.getElementById('progress').classList.remove('hidden');
    document.getElementById('results').classList.add('hidden');

    displayQuestion();
}

// Start quiz with only wrong questions
function startQuizWrongOnly() {
    if (wrongQuestionIds.length === 0) {
        alert('No incorrectly answered questions saved!');
        return;
    }

    currentQuestions = allQuestions.filter(q => wrongQuestionIds.includes(q.id));
    currentQuestions = shuffleArray(currentQuestions);

    currentQuestionIndex = 0;
    questionsAnswered = 0;
    correctCount = 0;
    wrongCount = 0;

    examMode = false;

    document.getElementById('controls').classList.add('hidden');
    document.getElementById('quizCard').classList.remove('hidden');
    document.getElementById('progress').classList.remove('hidden');
    document.getElementById('results').classList.add('hidden');

    displayQuestion();
}

// Save wrong questions to localStorage
function saveWrongQuestions() {
    localStorage.setItem(`wrongQuestions_${currentCatalog}`, JSON.stringify(wrongQuestionIds));
}

// Load wrong questions from localStorage
function loadWrongQuestions() {
    const saved = localStorage.getItem(`wrongQuestions_${currentCatalog}`);
    wrongQuestionIds = saved ? JSON.parse(saved) : [];
}

// Save seen questions to localStorage
function saveSeenQuestions() {
    localStorage.setItem(`seenQuestions_${currentCatalog}`, JSON.stringify(seenQuestionIds));
}

// Load seen questions from localStorage
function loadSeenQuestions() {
    const saved = localStorage.getItem(`seenQuestions_${currentCatalog}`);
    seenQuestionIds = saved ? JSON.parse(saved) : [];
}

// Clear all progress for current catalog
function clearProgress() {
    const config = CATALOGS[currentCatalog];
    const catalogName = config ? config.name : currentCatalog;

    if (confirm(`Reset your learning progress for "${catalogName}"?\n\n- Seen questions\n- Incorrectly answered questions\n\nThis action cannot be undone!`)) {
        wrongQuestionIds = [];
        seenQuestionIds = [];
        saveWrongQuestions();
        saveSeenQuestions();
        alert('Progress has been reset!');
        updateProgressDisplay();
    }
}

// Update progress display in controls
function updateProgressDisplay() {
    const progressInfo = document.getElementById('progressInfo');
    if (!progressInfo) return;

    const totalQuestions = allQuestions.length;
    const seenCount = seenQuestionIds.length;
    const wrongCountDisplay = wrongQuestionIds.length;
    const unseenCount = totalQuestions - seenCount;
    const percentage = totalQuestions > 0 ? Math.round((seenCount / totalQuestions) * 100) : 0;

    const config = CATALOGS[currentCatalog];
    const passingScore = config ? config.passingScore : '?';

    let html = '<div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">';
    html += '<div style="margin-bottom: 10px;"><strong>Learning Progress:</strong></div>';
    html += `<div style="margin-bottom: 5px;">Completed: <strong>${seenCount} / ${totalQuestions}</strong> (${percentage}%)</div>`;
    html += `<div style="margin-bottom: 5px;">New questions: <strong>${unseenCount}</strong></div>`;
    html += `<div style="margin-bottom: 5px;">Incorrect: <strong>${wrongCountDisplay}</strong></div>`;
    html += `<div>Passing score: <strong>${passingScore}%</strong></div>`;
    html += '</div>';

    progressInfo.innerHTML = html;
}

// Utility: Shuffle array (Fisher-Yates)
function shuffleArray(array) {
    const arr = [...array];
    for (let i = arr.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
}

// Shuffle answers within a question and update correct index
function shuffleAnswers(question) {
    const indices = question.answers.map((_, idx) => idx);
    const shuffledIndices = shuffleArray(indices);

    const newAnswers = shuffledIndices.map(idx => question.answers[idx]);
    question.answers = newAnswers;

    if (Array.isArray(question.correct)) {
        question.correct = question.correct.map(correctIdx => shuffledIndices.indexOf(correctIdx));
    } else {
        question.correct = shuffledIndices.indexOf(question.correct);
    }
}

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
    if (document.getElementById('quizCard').classList.contains('hidden')) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;

    const question = currentQuestions[currentQuestionIndex];
    if (!question) return;

    const feedbackShown = !document.getElementById('feedbackSection').classList.contains('hidden');

    if (feedbackShown) {
        if (e.key === ' ' || e.key === 'Enter' || e.key === 'ArrowRight' || e.key === 'ArrowDown') {
            const continueBtn = document.querySelector('#feedbackSection button');
            if (continueBtn) continueBtn.click();
            e.preventDefault();
        }
    } else {
        if (!question.multiple_choice) {
            const key = e.key.toLowerCase();
            if (key >= '1' && key <= '9') {
                const index = parseInt(key) - 1;
                if (index < question.answers.length) selectAnswer(index);
            }
            if (key >= 'a' && key <= 'z') {
                const index = key.charCodeAt(0) - 97;
                if (index < question.answers.length) selectAnswer(index);
            }
        } else {
            if (e.key === 'Enter') {
                const submitBtn = document.querySelector('#question button');
                if (submitBtn && submitBtn.style.display !== 'none') checkAnswer();
            }
        }
    }
});

// Initialize
loadQuestions();
