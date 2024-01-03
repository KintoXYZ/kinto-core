module.exports = async ({ github, context, header, body }) => {
  const comment = [header, body].join("\n");

  let issueNumber;

  if (context.eventName === 'pull_request') {
      // For pull_request events, the number is directly available
      issueNumber = context.payload.pull_request.number;
      console.log("Pull Request Number: ", issueNumber);
  } else if (context.eventName === 'push') {
      // For push events, try to get the associated pull requests
      const pullRequests = await github.rest.pulls.list({
          owner: context.repo.owner,
          repo: context.repo.repo,
          state: 'open',
          head: `${context.repo.owner}:${context.ref.replace('refs/heads/', '')}`
      });

      if (pullRequests.data.length > 0) {
          // If there are open pull requests associated with the push, take the first one
          issueNumber = pullRequests.data[0].number;
          console.log("Associated Pull Request Number: ", issueNumber);
      } else {
          console.log("No associated pull requests found for this push event.");
          return;  // Exit early if no associated PR is found
      }
  } else {
      // If the event is neither pull_request nor push, log it and exit
      console.log(`Unhandled event type: ${context.eventName}`);
      return;
  }

  // Get the existing comments
  const { data: comments } = await github.rest.issues.listComments({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: issueNumber,
  });

  // Find any comment already made by the bot
  const botComment = comments.find(
      comment => comment.user.id === 41898282 && comment.body.startsWith(header)
  );

  const commentFn = botComment ? "updateComment" : "createComment";

  // Create or update the comment
  await github.rest.issues[commentFn]({
      owner: context.repo.owner,
      repo: context.repo.repo,
      body: comment,
      ...(botComment
          ? { comment_id: botComment.id }
          : { issue_number: issueNumber }),
  });
};
